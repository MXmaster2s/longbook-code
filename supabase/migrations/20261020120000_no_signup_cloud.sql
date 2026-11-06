-- longbook is bought before it is used, so signing up no longer starts three days of Cloud.
-- Cloud comes from a subscription or a grant (the licence's twelve months) alone.
-- profiles.trial_started_at stays until no shipped app reads it.
create or replace function public.cloud_until(uid uuid)
returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select greatest(
    (select s.expires_at from public.cloud_subscriptions s
       where s.user_id = uid and s.status in ('active', 'grace')),
    (select g.until from public.cloud_grants g where g.user_id = uid)
  )
$$;

revoke all on function public.cloud_until(uuid) from public, anon, authenticated, service_role;
