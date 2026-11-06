-- One paid Polar order licenses one account at a time: a second active licence naming the same
-- order is refused by the database, whatever the two requests racing for it did first. Only a
-- real order id counts (a UUID); hand grants carry a label such as owner-grant, and several
-- accounts may hold one.
create unique index entitlements_polar_order_active
  on public.entitlements (polar_order_id)
  where status = 'active'
    and polar_order_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
