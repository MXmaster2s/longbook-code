-- A shared report whose link expired stays until someone opens the link or its owner
-- revokes it. Each night every expired share goes, and its comments with it.
create or replace function public.expire_shared_reports()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  gone integer;
begin
  with deleted as (
    delete from shared_reports where expires_at < now() returning 1
  )
  select count(*) into gone from deleted;
  return gone;
end;
$$;

revoke all on function public.expire_shared_reports() from public, anon, authenticated;

-- 03:23 UTC, every night, after the hosted-copy expiry.
select cron.schedule('expire-shared-reports', '23 3 * * *', $$select public.expire_shared_reports()$$);
