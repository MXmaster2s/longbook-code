-- One row per statement a signed-in user reads through the server: how many model calls
-- it took and how many tokens they spent. The function alone writes here, with the
-- service role; it refuses the next piece once an import has spent its budget, and the
-- next file once the user has read their share this month. No client may touch it.
create table public.statement_imports (
  user_id uuid not null references auth.users (id) on delete cascade,
  import_id text not null check (char_length(import_id) between 8 and 64),
  started_at timestamptz not null default now(),
  last_call_at timestamptz not null default now(),
  calls integer not null default 0,
  tokens integer not null default 0,
  primary key (user_id, import_id)
);

create index statement_imports_user_started on public.statement_imports (user_id, started_at desc);

alter table public.statement_imports enable row level security;
revoke all on public.statement_imports from anon, authenticated;
