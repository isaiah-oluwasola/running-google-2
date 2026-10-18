-- HeyApp file sharing: paste this whole file into Supabase -> SQL Editor -> Run. Safe to run twice.
create table if not exists file_transfers (
  id text primary key,
  sender_id text not null, receiver_id text not null,
  name text not null, size bigint not null, mime text,
  mode text default 'p2p',
  status text not null default 'created',   -- created | uploaded | delivered
  cloud_public_id text, cloud_resource_type text, cloud_version text,
  created_at timestamptz default now(),
  expires_at timestamptz not null,
  delivered_at timestamptz
);
create index if not exists ft_receiver_pending on file_transfers(receiver_id, status);
alter table file_transfers disable row level security;   -- same as the rest of your app's tables
grant all on file_transfers to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('heyapp-files', 'heyapp-files', false, 52428800)
on conflict (id) do update set file_size_limit = 52428800, public = false;

drop policy if exists "heyapp files access" on storage.objects;
create policy "heyapp files access" on storage.objects for all to anon, authenticated
  using (bucket_id = 'heyapp-files') with check (bucket_id = 'heyapp-files');
