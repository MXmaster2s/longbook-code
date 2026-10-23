-- An app that was uninstalled never says goodbye, so a hosted copy would outlive it. Each
-- night, a copy the app has not refreshed for ninety days goes, and with it any proposal
-- that old. The app refreshes the copy once a day while it is in use.
create extension if not exists pg_cron;

create or replace function public.expire_hosted_copies()
returns table (copies integer, proposals integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  gone_copies integer;
  gone_proposals integer;
begin
  with gone as (
    delete from hosted_memories where pushed_at < now() - interval '90 days' returning 1
  )
  select count(*) into gone_copies from gone;
  with gone as (
    delete from mcp_pending_writes where created_at < now() - interval '90 days' returning 1
  )
  select count(*) into gone_proposals from gone;
  return query select gone_copies, gone_proposals;
end;
$$;

revoke all on function public.expire_hosted_copies() from public, anon, authenticated;

-- 03:17 UTC, every night. Scheduling under one name replaces an earlier schedule of it.
select cron.schedule('expire-hosted-copies', '17 3 * * *', $$select public.expire_hosted_copies()$$);
