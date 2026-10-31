-- The licence has two sellers: the App Store, and Polar on longbook.app. Each licence names the
-- source that wrote it, and every web order is kept, whether or not an account has claimed it
-- yet: the email, order id, country, amount and refund status, never the name or billing address.
alter table public.entitlements
  add column source text not null default 'apple' check (source in ('apple', 'polar', 'grant')),
  add column polar_customer_id text,
  add column polar_license_key_id text;

update public.entitlements set source = 'polar' where polar_order_id is not null;

-- A licence with no seller's id on it was granted by hand. Family copies and licences moved to
-- another account carry Apple's environment, so they stay Apple's.
update public.entitlements set source = 'grant'
where polar_order_id is null
  and apple_original_transaction_id is null
  and apple_family_transaction_id is null
  and apple_environment is null;

create index entitlements_polar_order on public.entitlements (polar_order_id)
  where polar_order_id is not null;

-- Reads of entitlements are granted column by column (20260909112000); the new columns are
-- the server's alone, withdrawn by name so no earlier grant can carry them.
revoke select (source, polar_customer_id, polar_license_key_id) on table public.entitlements
  from anon, authenticated;

-- One row per Polar order for the licence, written only by the polar functions with the
-- service role. amount is in minor units. environment keeps sandbox orders out of the seat count.
-- Deleting the account empties every column that names the buyer, email included; the order's
-- figures stay for seats and tax. claimed_at set with user_id null marks such a row.
create table public.web_orders (
  order_id text primary key,
  user_id uuid references auth.users (id) on delete set null,
  email text,
  polar_customer_id text,
  external_customer_id text,
  product_id text not null,
  amount integer not null,
  currency text not null,
  country text,
  status text not null check (status in ('paid', 'refunded')),
  environment text not null default 'production' check (environment in ('production', 'sandbox')),
  license_key_id text,
  paid_at timestamptz not null,
  refunded_at timestamptz,
  claimed_at timestamptz,
  claimed_by uuid,
  created_at timestamptz not null default now()
);

create index web_orders_customer on public.web_orders (polar_customer_id)
  where polar_customer_id is not null;
create index web_orders_license_key on public.web_orders (license_key_id)
  where license_key_id is not null;
create index web_orders_seats on public.web_orders (paid_at)
  where status = 'paid' and environment = 'production' and amount > 0;

alter table public.web_orders enable row level security;
revoke all on table public.web_orders from public, anon, authenticated;
