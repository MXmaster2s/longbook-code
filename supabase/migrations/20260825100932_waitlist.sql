-- The pre-release list. The Mac build is not final, so the download controls ask for an address
-- instead of handing over a file, and the address lands here. One row per address; nothing else
-- about the person is kept. Applied to the live project 2026-08-25.
create table public.waitlist (
  email text primary key,
  created_at timestamptz not null default now(),
  source text
);

-- No policies on purpose: only the waitlist function, holding the service role, writes here.
-- RLS with no policies keeps every ordinary role — anon included — out entirely.
alter table public.waitlist enable row level security;

-- A fixed-window counter per caller, so a public form cannot be turned into a thousand rows.
-- Same shape as mcp_rate: counted in place, nothing accumulates.
create table public.waitlist_rate (
  subject text primary key,
  window_start timestamptz not null,
  count integer not null
);

alter table public.waitlist_rate enable row level security;

create or replace function public.waitlist_rate_bump(p_subject text, p_limit integer)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  win timestamptz := date_trunc('hour', now());
  n integer;
begin
  insert into waitlist_rate as r (subject, window_start, count) values (p_subject, win, 1)
    on conflict (subject) do update set
      count = case when r.window_start = win then r.count + 1 else 1 end,
      window_start = win
    returning r.count into n;
  return n <= p_limit;
end $$;

revoke all on function public.waitlist_rate_bump(text, integer) from public;
grant execute on function public.waitlist_rate_bump(text, integer) to service_role;
