-- longbook Support: a day's count of questions per asker, and one row per answer saying
-- which articles answered it (or, unanswered, a short topic) and its rating. Never the
-- messages. Service role only.
create table public.support_asks (
  asker text not null,
  day date not null default current_date,
  asks integer not null default 0,
  primary key (asker, day)
);

create table public.support_answers (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  answered boolean not null,
  articles text[] not null default '{}',
  gap text,
  rating text check (rating in ('up', 'down')),
  -- The hash of a key only the asker's app or page holds, so only they can rate the answer.
  rate_key text
);

alter table public.support_asks enable row level security;
alter table public.support_answers enable row level security;
revoke all on public.support_asks, public.support_answers from public, anon, authenticated;

-- One question counted, as an increment: two asked together must both count. Returns the
-- day's count after this one. Counts older than yesterday go on the way, as the policy says.
create function public.support_ask(p_asker text)
returns integer
language sql
security definer
set search_path = public
as $$
  delete from public.support_asks where day < current_date - 1;
  insert into public.support_asks (asker, day, asks) values (p_asker, current_date, 1)
  on conflict (asker, day) do update set asks = public.support_asks.asks + 1
  returning asks;
$$;

revoke all on function public.support_ask(text) from public, anon, authenticated;
