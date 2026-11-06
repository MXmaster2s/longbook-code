-- The pre-release list has done its work: the site no longer collects addresses, so the
-- table, its rate counter and the counter's function go, with the rows they held.
drop function if exists public.waitlist_rate_bump(text, integer);
drop table if exists public.waitlist_rate;
drop table if exists public.waitlist;
