-- Emails to a person about their own account: a sign-in, the hosted copy turned on or off, a
-- report shared. An event writes a row here; the account-notice function sends it. No app or
-- browser can read or write this table.
create extension if not exists pg_net;

create table public.account_notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('signin', 'mcp_on', 'mcp_off', 'report_shared')),
  details jsonb not null default '{}'::jsonb,
  dedupe_key text unique,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  sent_at timestamptz,
  skipped_reason text,
  attempts integer not null default 0
);
create index account_notices_waiting on public.account_notices (created_at)
  where sent_at is null and skipped_reason is null;
create index account_notices_sent on public.account_notices (user_id, kind, sent_at);
alter table public.account_notices enable row level security;
revoke all on table public.account_notices from public, anon, authenticated;
revoke truncate, trigger, references on table public.account_notices from public, anon, authenticated;

-- How far the sign-in scan has read. It starts now, so no earlier sign-in is announced late.
create table public.notice_cursor (
  name text primary key,
  seen_until timestamptz not null
);
insert into public.notice_cursor (name, seen_until) values ('sessions', now());
alter table public.notice_cursor enable row level security;
revoke all on table public.notice_cursor from public, anon, authenticated;
revoke truncate, trigger, references on table public.notice_cursor from public, anon, authenticated;

-- The hosted copy turned on is a first insert; turned off is the owner deleting it. The nightly
-- expiry and an account's deletion have no signed-in owner, so they say nothing. A notice must
-- never block the owner's own write, so any failure here is swallowed.
create or replace function public.notice_hosted_copy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and (select auth.uid()) is not distinct from new.user_id then
    insert into public.account_notices (user_id, kind, details)
    values (new.user_id, 'mcp_on', jsonb_build_object('at', now()));
  elsif tg_op = 'DELETE' and (select auth.uid()) is not distinct from old.user_id then
    insert into public.account_notices (user_id, kind, details)
    values (old.user_id, 'mcp_off', jsonb_build_object('at', now()));
  end if;
  return null;
exception when others then
  return null;
end;
$$;
revoke all on function public.notice_hosted_copy() from public, anon, authenticated;

create trigger hosted_memories_notice
  after insert or delete on public.hosted_memories
  for each row execute function public.notice_hosted_copy();

-- New sessions since the last scan, read back five minutes for late commits. A session within two
-- hours of the account being confirmed is the sign-up itself, and a connected AI's session is not
-- a sign-in. Reading sessions, not a trigger on them, leaves sign-in untouched.
create or replace function public.scan_new_sessions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  upto timestamptz := now() - interval '10 seconds';
  added integer;
begin
  insert into public.account_notices (user_id, kind, details, dedupe_key)
  select s.user_id, 'signin',
         jsonb_build_object(
           'at', s.created_at,
           'user_agent', left(s.user_agent, 200),
           'ip', host(s.ip),
           'method', (select c.authentication_method from auth.mfa_amr_claims c
                      where c.session_id = s.id order by c.created_at limit 1)),
         'session:' || s.id
  from auth.sessions s
  join auth.users u on u.id = s.user_id
  where s.created_at > (select seen_until from public.notice_cursor where name = 'sessions') - interval '5 minutes'
    and s.created_at <= upto
    and s.oauth_client_id is null
    and s.created_at - coalesce(u.email_confirmed_at, u.created_at) > interval '2 hours'
  on conflict (dedupe_key) do nothing;
  get diagnostics added = row_count;
  update public.notice_cursor set seen_until = upto where name = 'sessions';
  return added;
end;
$$;
revoke all on function public.scan_new_sessions() from public, anon, authenticated;

-- Calls the function while any notice waits, with the key kept in the vault. Without the key, or
-- with nothing waiting, it does nothing.
create or replace function public.poke_account_notices()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  notice_key text;
begin
  if not exists (
    select 1 from public.account_notices
    where sent_at is null and skipped_reason is null and attempts < 5
      and created_at > now() - interval '2 days'
      and (claimed_at is null or claimed_at < now() - interval '5 minutes' * greatest(attempts, 1))
  ) then
    return;
  end if;
  select decrypted_secret into notice_key from vault.decrypted_secrets where name = 'notice_key';
  if notice_key is null then
    return;
  end if;
  perform net.http_post(
    url := 'https://xbrnijgctmovoqbbmgmb.supabase.co/functions/v1/account-notice',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-notice-key', notice_key),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
end;
$$;
revoke all on function public.poke_account_notices() from public, anon, authenticated;

-- Takes waiting notices for one run. Rows another run holds are skipped. A notice that failed or
-- was never finished is offered again after five minutes, then ten, and so on, up to five tries.
create or replace function public.claim_account_notices(max_rows integer default 20)
returns setof public.account_notices
language sql
security definer
set search_path = ''
as $$
  update public.account_notices n
  set claimed_at = now(), attempts = n.attempts + 1
  where n.id in (
    select w.id from public.account_notices w
    where w.sent_at is null and w.skipped_reason is null and w.attempts < 5
      and w.created_at > now() - interval '2 days'
      and (w.claimed_at is null or w.claimed_at < now() - interval '5 minutes' * greatest(w.attempts, 1))
    order by w.created_at
    limit max_rows
    for update skip locked
  )
  returning n.*;
$$;
revoke all on function public.claim_account_notices(integer) from public, anon, authenticated;
grant execute on function public.claim_account_notices(integer) to service_role;

-- Hourly: a notice that ran out of tries, or waited two days, is given up and what it recorded is
-- dropped; records go after thirty days, and this job's run history after seven.
create or replace function public.tidy_account_notices()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.account_notices
  set skipped_reason = 'gave_up', details = '{}'::jsonb
  where sent_at is null and skipped_reason is null
    and (created_at < now() - interval '2 days'
         or (attempts >= 5 and claimed_at < now() - interval '10 minutes'));
  delete from public.account_notices where created_at < now() - interval '30 days';
  delete from cron.job_run_details
  where end_time < now() - interval '7 days'
    and jobid in (select jobid from cron.job where jobname like 'account-notices-%');
end;
$$;
revoke all on function public.tidy_account_notices() from public, anon, authenticated;

-- Three jobs, so a fault in one cannot stop the others: read new sign-ins and call the function
-- every minute, and tidy each hour. Scheduling under a name replaces an earlier schedule of it.
select cron.schedule('account-notices-scan', '* * * * *', $$select public.scan_new_sessions()$$);
select cron.schedule('account-notices-send', '* * * * *', $$select public.poke_account_notices()$$);
select cron.schedule('account-notices-tidy', '17 * * * *', $$select public.tidy_account_notices()$$);
