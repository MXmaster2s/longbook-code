-- The trial is three days. cloud_until counted fourteen; this re-creates it with three, so
-- has_cloud and the nightly expiry follow. Nothing else about Cloud changes.
create or replace function public.cloud_until(uid uuid)
returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select greatest(
    (select p.trial_started_at + interval '3 days' from public.profiles p where p.id = uid),
    (select s.expires_at from public.cloud_subscriptions s
       where s.user_id = uid and s.status in ('active', 'grace')),
    (select g.until from public.cloud_grants g where g.user_id = uid)
  )
$$;

revoke all on function public.cloud_until(uuid) from public, anon, authenticated, service_role;
