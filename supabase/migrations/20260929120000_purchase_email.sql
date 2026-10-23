-- When the confirmation email for a purchase was sent. apple-purchase claims it before sending, so
-- a restore or a repeat delivery finds it taken, and gives it back if the send fails.
-- No client can read it: entitlements grants clients named columns only, and this is not one.
alter table public.entitlements
  add column purchase_email_sent_at timestamptz;

-- Every licence that exists now was confirmed by other means. Marked as handled, so the next
-- restore does not tell someone their licence is "now active" weeks after they bought it.
update public.entitlements
set purchase_email_sent_at = purchased_at
where purchase_email_sent_at is null;
