-- Where each account's first run stands, written by the app after every onboarding step so
-- a second device can open on the Waiting screen and resume. One row per account, the
-- owner's alone. Holds a stage word and a device name, never anything from the vault.
create table if not exists public.onboarding_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  stage text not null,
  device text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.onboarding_progress enable row level security;

create policy "onboarding_progress_select_own" on public.onboarding_progress
  for select using (auth.uid() = user_id);
create policy "onboarding_progress_insert_own" on public.onboarding_progress
  for insert with check (auth.uid() = user_id);
create policy "onboarding_progress_update_own" on public.onboarding_progress
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "onboarding_progress_delete_own" on public.onboarding_progress
  for delete using (auth.uid() = user_id);

revoke all on public.onboarding_progress from anon;
grant select, insert, update, delete on public.onboarding_progress to authenticated;
