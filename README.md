# HeyApp file sharing — setup (about 10 minutes)

1. **Database** — Supabase → SQL editor → paste `schema.sql` → Run.
2. **Cloudinary** — free account at cloudinary.com. From the dashboard note: Cloud name, API Key, API Secret.
3. **Deploy the backend** (needs Supabase CLI: `npm i -g supabase`):
   ```
   supabase login
   supabase link --project-ref pgjxbcsircqtkmzdafhy
   supabase secrets set CLOUDINARY_CLOUD_NAME=xxx CLOUDINARY_API_KEY=xxx CLOUDINARY_API_SECRET=xxx \
       FIREBASE_PROJECT_ID=sayhi-2026 CRON_SECRET=any-long-random-string
   supabase functions deploy file-transfer --no-verify-jwt
   ```
4. **Auto-cleanup** (optional) — Supabase → Database → Cron: daily
   POST `https://pgjxbcsircqtkmzdafhy.supabase.co/functions/v1/file-transfer`
   header `x-cron-secret: <CRON_SECRET>`, body `{"action":"purge"}`.
5. **Host `index.html`** over https (Vercel/Netlify). Firebase → Authentication → Settings → Authorized domains: add your domain.
6. Open on two devices, sign in as two users, tap 📎.

Tip: P2P behind strict mobile/corporate NATs may fail with STUN only; the app then falls back to cloud automatically. Add a TURN server to `ICE_SERVERS` for better P2P rates.
