-- Launch pricing counts App Store licences bought, not copies a family member receives through
-- Family Sharing. A family copy is a licence for that member's own account, recorded without the
-- purchase's unique id so the buyer keeps it; its id sits beside it for refunds and revocations.
alter table public.entitlements
  add column apple_ownership text check (apple_ownership in ('PURCHASED', 'FAMILY_SHARED')),
  add column apple_family_transaction_id text;

create index entitlements_family_transaction on public.entitlements (apple_family_transaction_id)
  where apple_family_transaction_id is not null;

-- Each price step, once applied: claimed before the App Store is asked, so two sales landing
-- together raise the price once. The function alone writes here, with the service role.
create table public.licence_price_steps (
  tier integer primary key,
  price text not null,
  sold integer not null,
  claimed_at timestamptz not null default now(),
  applied_at timestamptz,
  error text
);

alter table public.licence_price_steps enable row level security;
revoke all on public.licence_price_steps from anon, authenticated;
-- The two new entitlements columns stay unreadable to clients: that table's reads are granted
-- column by column (20260909112000), and these are not granted.
