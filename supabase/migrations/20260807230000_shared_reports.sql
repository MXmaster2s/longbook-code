-- Report sharing: a report the owner chose to share, copied out of the vault as one JSON
-- value, behind a password and a deadline. The vault itself never comes near this server —
-- see docs/report-sharing.md.

create table if not exists shared_reports (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  report jsonb not null,
  password_hash text not null,
  password_salt text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
alter table shared_reports enable row level security;
-- No client policies at all — viewers hold no Supabase session, so every read and write goes
-- through the share-report Edge Function with the service-role key, which bypasses RLS.

-- Expiry checks look rows up by deadline.
create index if not exists shared_reports_expires_at_idx on shared_reports (expires_at);

create table if not exists report_comments (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references shared_reports(id) on delete cascade,
  module_id text not null,
  author text,
  body text not null,
  created_at timestamptz not null default now()
);
alter table report_comments enable row level security;
-- Same as shared_reports: no client policies, service-role only. Revoking a share deletes its
-- row, and the cascade removes every comment with it.

create index if not exists report_comments_share_id_idx on report_comments (share_id);
