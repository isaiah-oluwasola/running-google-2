-- Run in Supabase SQL editor. RLS ON with no policies = only the edge function (service role) can touch it.
create table if not exists file_transfers (
  id text primary key,                 -- transfer id (client-generated uuid)
  sender_id text not null,
  receiver_id text not null,
  name text not null, size bigint not null, mime text,
  mode text default 'p2p',             -- p2p | cloud
  status text not null default 'created', -- created | uploaded | delivered | failed | expired
  cloud_public_id text, cloud_resource_type text, cloud_version text,
  created_at timestamptz default now(),
  expires_at timestamptz not null,
  delivered_at timestamptz
);
create index if not exists ft_receiver_pending on file_transfers(receiver_id, status);
alter table file_transfers enable row level security;
