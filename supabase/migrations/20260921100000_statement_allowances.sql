-- "Contact us for more usage rights" needs a place to grant them: one account's own number
-- of statement imports a month. The statement reader alone reads it, with the service
-- role; an account without a row keeps the default. No client may touch it.
create table public.statement_allowances (
  user_id uuid primary key references auth.users (id) on delete cascade,
  imports_per_month integer not null check (imports_per_month between 0 and 1000),
  note text,
  granted_at timestamptz not null default now()
);

alter table public.statement_allowances enable row level security;
revoke all on public.statement_allowances from anon, authenticated;
