-- Belt as well as braces. Row-level security with no policies already refuses every ordinary
-- role, but the table grants are withdrawn too, so anon and authenticated cannot reach the list
-- even if a policy is ever added by accident. Only the service role, held by the waitlist
-- function, and the dashboard reach it. Applied to the live project 2026-08-25.
revoke all on table public.waitlist from anon, authenticated;
revoke all on table public.waitlist_rate from anon, authenticated;
