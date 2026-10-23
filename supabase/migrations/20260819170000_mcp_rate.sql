-- A durable floor under the hosted MCP rate limit. The in-memory limiter guards one
-- isolate; this row-per-caller counter survives cold starts and parallel isolates, so
-- 30 a minute means 30 a minute. Fixed window, counted in place — nothing accumulates.
-- Applied to the live project 2026-08-19.
create table public.mcp_rate (
  subject text primary key,
  window_start timestamptz not null,
  count integer not null
);

-- No policies on purpose: only the definer functions below touch this table, and RLS
-- with no policies keeps every ordinary role out entirely.
alter table public.mcp_rate enable row level security;

-- Count one call against the subject's current minute. Granted to nobody: reachable
-- only through the two doors below, each of which names its own subject.
create or replace function public.mcp_rate_bump(p_subject text)
returns table (allowed boolean, retry_after integer)
language plpgsql security definer set search_path = public as $$
declare
  win timestamptz := date_trunc('minute', now());
  n integer;
begin
  insert into mcp_rate as r (subject, window_start, count) values (p_subject, win, 1)
    on conflict (subject) do update set
      count = case when r.window_start = win then r.count + 1 else 1 end,
      window_start = win
    returning r.count into n;
  return query select n <= 30,
    greatest(1, ceil(extract(epoch from (win + interval '1 minute') - now()))::integer);
end $$;

revoke all on function public.mcp_rate_bump(text) from public;

-- The JWT door. The subject comes from the caller's own token, never from an argument,
-- so no caller can spend another's allowance or write junk subjects into the table.
create or replace function public.mcp_rate_check()
returns table (allowed boolean, retry_after integer)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return query select false, 60;
    return;
  end if;
  return query select * from mcp_rate_bump(auth.uid()::text);
end $$;

revoke all on function public.mcp_rate_check() from public;
grant execute on function public.mcp_rate_check() to authenticated;

-- The key door: redemption and the rate count in one definer call. The return shape
-- grows two columns, which is a signature change, so the function is recreated. A junk
-- hash still answers nothing and writes nothing — spam cannot bloat the counter table.
drop function public.mcp_memory_for_key(text);

create function public.mcp_memory_for_key(p_key_hash text)
returns table (key_id uuid, memory jsonb, allowed boolean, retry_after integer)
language plpgsql security definer set search_path = public as $$
declare k record; gate record;
begin
  select ak.id, ak.user_id into k
    from access_keys ak
    where ak.key_hash = p_key_hash and ak.revoked_at is null;
  if not found then return; end if;
  update access_keys set last_used_at = now() where id = k.id;
  select * into gate from mcp_rate_bump('key:' || k.id::text);
  if not gate.allowed then
    return query select k.id, null::jsonb, false, gate.retry_after;
    return;
  end if;
  return query select k.id, hm.memory, true, gate.retry_after
    from hosted_memories hm where hm.user_id = k.user_id;
  if not found then
    return query select k.id, null::jsonb, true, gate.retry_after;
  end if;
end $$;

revoke all on function public.mcp_memory_for_key(text) from public;
grant execute on function public.mcp_memory_for_key(text) to anon, authenticated;
