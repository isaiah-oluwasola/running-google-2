# HeyApp file sharing — 2 steps
1. Supabase → SQL Editor → paste all of `schema.sql` → Run.
2. Replace your hosted `index.html` with this one (Vercel), then hard-refresh.
That's it. No Cloudinary, no keys, no settings.
Limits: 50 MB for offline (cloud) delivery; direct P2P has no practical limit.
(If Supabase's own storage limit is lower: Project Settings → Storage → Global file size limit.)
