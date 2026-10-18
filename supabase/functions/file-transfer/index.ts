// Deploy: supabase functions deploy file-transfer --no-verify-jwt
// Secrets: CLOUDINARY_CLOUD_NAME CLOUDINARY_API_KEY CLOUDINARY_API_SECRET FIREBASE_PROJECT_ID
//          CRON_SECRET RETENTION_DAYS(default 7) MAX_CLOUD_BYTES(default 104857600)
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "https://esm.sh/jose@5";

const env = (k: string, d = "") => Deno.env.get(k) ?? d;
const CLOUD = env("CLOUDINARY_CLOUD_NAME"), KEY = env("CLOUDINARY_API_KEY"), SECRET = env("CLOUDINARY_API_SECRET");
const PROJECT = env("FIREBASE_PROJECT_ID"), RETAIN = +env("RETENTION_DAYS", "7"), MAX = +env("MAX_CLOUD_BYTES", "104857600");
const BLOCKED = /\.(exe|bat|cmd|scr|msi|com|vbs|js|jar|apk|sh|ps1|dll)$/i;
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
const jwks = createRemoteJWKSet(new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"));
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type", "Content-Type": "application/json" };
const out = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: cors });

const sha1 = async (s: string) => new Uint8Array(await crypto.subtle.digest("SHA-1", new TextEncoder().encode(s)));
const hex = (u: Uint8Array) => [...u].map(b => b.toString(16).padStart(2, "0")).join("");
const sign = async (p: Record<string, string>) =>
  hex(await sha1(Object.keys(p).sort().map(k => `${k}=${p[k]}`).join("&") + SECRET));
const deliveryUrl = async (rt: string, ver: string, pid: string) => {
  const sig = btoa(String.fromCharCode(...(await sha1(pid + SECRET)))).replace(/\+/g, "-").replace(/\//g, "_").slice(0, 8);
  return `https://res.cloudinary.com/${CLOUD}/${rt}/authenticated/s--${sig}--/v${ver}/${pid}`;
};
async function destroy(t: any) {
  if (!t.cloud_public_id) return;
  const p = { public_id: t.cloud_public_id, type: "authenticated", timestamp: String(Math.floor(Date.now() / 1000)) };
  const body = new URLSearchParams({ ...p, api_key: KEY, signature: await sign(p) });
  const r = await fetch(`https://api.cloudinary.com/v1_1/${CLOUD}/${t.cloud_resource_type}/destroy`, { method: "POST", body });
  if (!r.ok) throw new Error("cloudinary destroy " + r.status);
  await db.from("file_transfers").update({ cloud_public_id: null }).eq("id", t.id);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return out({});
  try {
    const a = await req.json();
    if (a.action === "purge") { // call from a cron with x-cron-secret
      if (req.headers.get("x-cron-secret") !== env("CRON_SECRET")) return out({ error: "forbidden" }, 403);
      const { data } = await db.from("file_transfers").select("*").lt("expires_at", new Date().toISOString()).not("cloud_public_id", "is", null);
      let n = 0; for (const t of data ?? []) { try { await destroy(t); await db.from("file_transfers").update({ status: t.status === "delivered" ? "delivered" : "expired" }).eq("id", t.id); n++; } catch (_) {} }
      return out({ purged: n });
    }
    const tok = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "");
    const { payload } = await jwtVerify(tok, jwks, { issuer: `https://securetoken.google.com/${PROJECT}`, audience: PROJECT });
    const uid = payload.sub as string;
    const own = async (id: string, col: "sender_id" | "receiver_id") => {
      const { data } = await db.from("file_transfers").select("*").eq("id", id).maybeSingle();
      if (!data || data[col] !== uid) throw new Error("not found");
      return data;
    };

    if (a.action === "init") { // register + (for cloud) get upload signature
      if (!a.id || !a.to || a.to === uid) return out({ error: "bad request" }, 400);
      const name = String(a.name ?? "").slice(0, 200), size = +a.size;
      if (!name || BLOCKED.test(name)) return out({ error: "File type not allowed" }, 400);
      if (a.mode === "cloud" && (!(size > 0) || size > MAX)) return out({ error: `Cloud limit is ${MAX / 1048576} MB` }, 400);
      const { data: ex } = await db.from("file_transfers").select("sender_id").eq("id", a.id).maybeSingle();
      if (ex && ex.sender_id !== uid) return out({ error: "conflict" }, 409);
      await db.from("file_transfers").upsert({ id: a.id, sender_id: uid, receiver_id: a.to, name, size, mime: a.mime ?? null, mode: a.mode,
        status: "created", expires_at: new Date(Date.now() + RETAIN * 864e5).toISOString() }, { onConflict: "id" });
      if (a.mode !== "cloud") return out({ ok: true });
      const p = { folder: "heyapp-transfers", public_id: a.id, timestamp: String(Math.floor(Date.now() / 1000)), type: "authenticated" };
      return out({ ok: true, cloud: CLOUD, api_key: KEY, ...p, signature: await sign(p) });
    }
    if (a.action === "complete") { // sender finished the Cloudinary upload
      const t = await own(a.id, "sender_id");
      if (t.status === "delivered") return out({ ok: true });
      await db.from("file_transfers").update({ status: "uploaded", mode: "cloud", cloud_public_id: String(a.public_id), cloud_resource_type: String(a.resource_type), cloud_version: String(a.version) }).eq("id", a.id);
      return out({ ok: true });
    }
    if (a.action === "pending") {
      const { data } = await db.from("file_transfers").select("id,sender_id,name,size,mime,created_at").eq("receiver_id", uid).eq("status", "uploaded").gt("expires_at", new Date().toISOString());
      return out({ items: data ?? [] });
    }
    if (a.action === "download") {
      const t = await own(a.id, "receiver_id");
      if (t.status !== "uploaded" || !t.cloud_public_id) return out({ error: "not available" }, 410);
      return out({ url: await deliveryUrl(t.cloud_resource_type, t.cloud_version, t.cloud_public_id) });
    }
    if (a.action === "ack") { // receiver confirms the file is saved on-device -> idempotent, then delete cloud copy
      const t = await own(a.id, "receiver_id");
      await db.from("file_transfers").update({ status: "delivered", delivered_at: new Date().toISOString() }).eq("id", a.id);
      try { await destroy(t); } catch (_) { /* purge job retries */ }
      return out({ ok: true });
    }
    if (a.action === "p2p-done") { // sender or receiver reports a verified P2P delivery
      const { data: t } = await db.from("file_transfers").select("*").eq("id", a.id).maybeSingle();
      if (!t || (t.sender_id !== uid && t.receiver_id !== uid)) return out({ error: "not found" }, 404);
      await db.from("file_transfers").update({ status: "delivered", delivered_at: new Date().toISOString() }).eq("id", a.id);
      try { await destroy(t); } catch (_) {}
      return out({ ok: true });
    }
    if (a.action === "status") {
      const { data } = await db.from("file_transfers").select("id,status").eq("sender_id", uid).in("id", (a.ids ?? []).slice(0, 50));
      return out({ items: data ?? [] });
    }
    return out({ error: "unknown action" }, 400);
  } catch (e) { return out({ error: String((e as Error).message ?? e) }, 401); }
});
