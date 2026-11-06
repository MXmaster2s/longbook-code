-- A licence bought through the App Store carries Apple's original transaction id and the
-- environment it was bought in, so a restore or a repeat delivery finds its own row and a
-- sandbox purchase is never mistaken for a sale. Polar's column stays; either may be null.
alter table public.entitlements
  add column apple_original_transaction_id text unique,
  add column apple_environment text check (apple_environment in ('Sandbox', 'Production'));
