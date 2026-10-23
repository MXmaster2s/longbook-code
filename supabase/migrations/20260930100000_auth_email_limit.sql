-- How many sign-in codes one address was sent in the last hour, so the auth-email function can
-- stop at the cap. Only a hash of the address is kept, and only for an hour. No app or browser
-- can read or write this table.
create table public.auth_email_sends (
  address_hash text not null,
  sent_at timestamptz not null default now()
);
create index auth_email_sends_recent on public.auth_email_sends (address_hash, sent_at);
alter table public.auth_email_sends enable row level security;
revoke all on table public.auth_email_sends from public, anon, authenticated;
revoke truncate, trigger, references on table public.auth_email_sends from public, anon, authenticated;

-- Counts one address's codes in the last hour, then every address together, and records this
-- one unless a cap is reached; then it says which and how long until the oldest falls out. One
-- address at a time, so two requests at once cannot both pass as the last allowed one.
create or replace function public.count_auth_email(address_hash text, cap integer, project_cap integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
  oldest timestamptz;
  total integer;
  first timestamptz;
begin
  perform pg_advisory_xact_lock(7, hashtext(count_auth_email.address_hash));
  delete from public.auth_email_sends where sent_at < now() - interval '1 hour';
  select count(*), min(s.sent_at) into n, oldest
  from public.auth_email_sends s
  where s.address_hash = count_auth_email.address_hash;
  if n >= cap then
    return jsonb_build_object(
      'allowed', false, 'reason', 'address',
      'retry_after_seconds', ceil(extract(epoch from (oldest + interval '1 hour' - now()))));
  end if;
  -- Every address together, read without a lock of its own: a ceiling, not an exact count.
  select count(*), min(sent_at) into total, first from public.auth_email_sends;
  if total >= project_cap then
    return jsonb_build_object(
      'allowed', false, 'reason', 'project',
      'retry_after_seconds', ceil(extract(epoch from (first + interval '1 hour' - now()))));
  end if;
  insert into public.auth_email_sends (address_hash) values (count_auth_email.address_hash);
  return jsonb_build_object('allowed', true, 'retry_after_seconds', 0);
end;
$$;
revoke all on function public.count_auth_email(text, integer, integer) from public, anon, authenticated;
grant execute on function public.count_auth_email(text, integer, integer) to service_role;
