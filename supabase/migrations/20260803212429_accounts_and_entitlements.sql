-- Paid-model accounts: identity, trial, and licence entitlement. A fresh project — unrelated to
-- any earlier schema. Never touches the financial memory file, which stays a plain file in the
-- user's own folder.

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  trial_started_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table profiles enable row level security;

create policy "a user reads only their own profile"
  on profiles for select
  to authenticated
  using (auth.uid() = id);
-- No insert/update/delete policy for anyone — profiles is written only by the trigger below
-- (security definer, fires once per new auth user) or the service-role key server-side.

create table if not exists entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  major_version integer not null,
  status text not null check (status in ('active', 'revoked')),
  polar_order_id text,
  purchased_at timestamptz not null default now()
);
alter table entitlements enable row level security;

create policy "a user reads only their own entitlement"
  on entitlements for select
  to authenticated
  using (auth.uid() = user_id);
-- Same as profiles: no client write policy. Entitlements are written only by the Polar
-- webhook's Edge Function, using the service-role key, which bypasses RLS entirely.

-- Creates the profile row, and with it the trial clock, the instant an account is created —
-- server time, at the one point a client cannot forge. Runs once per auth.users insert.
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, email) values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
