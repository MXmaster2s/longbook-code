-- The table-level SELECT hands every future column to the client. Named columns instead:
-- what the app reads, and nothing a later migration adds.
revoke select on table public.entitlements from authenticated;
grant select (user_id, major_version, status, polar_order_id, purchased_at)
  on table public.entitlements to authenticated;
