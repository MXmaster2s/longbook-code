-- Every licence is real or test. A test licence comes from a purchase that cost nothing:
-- Apple's sandbox (TestFlight, App Review, Xcode) or Polar's sandbox. Only an App Store copy
-- running in Apple's test environment unlocks with one. Rows already here stay real.
alter table public.entitlements
  add column kind text not null default 'real' check (kind in ('real', 'test'));

-- Reads of entitlements are granted column by column (20260909112000). The app reads kind
-- beside status to decide whether this copy unlocks.
grant select (kind) on table public.entitlements to authenticated;
