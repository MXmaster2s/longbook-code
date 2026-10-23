-- The signed-in door for reads, in one call. The hosted server used to make five round
-- trips for every request — Auth, the rate check, the memory, the inbox, a count — from a
-- function next to the caller to a database an ocean away, before it had read what the
-- request was for. This answers all five from the caller's own JWT in one statement.
--
-- A handshake (initialize, tools/list, a notification) asks with p_with_memory false and
-- gets the small columns only: the memory and the inbox stay in Tokyo. The names waiting
-- in to_fill_in ride along either way, so a connection learns its first job at once.
--
-- This is the lock on the door as well as the read. Nothing here asks Auth, so the
-- token's session must still be live in auth.sessions: Sign out all sessions and
-- Disconnect remove that row, and the connection ends with it, as the old door did. The
-- subject is auth.uid(), never an argument; no subject or no session answers no row,
-- which the door reads as not signed in. Modelled on mcp_memory_for_key. Granted to
-- authenticated alone.
create function public.mcp_memory_for_user(p_with_memory boolean default true)
returns table (
  allowed boolean,
  retry_after integer,
  email text,
  memory jsonb,
  pushed_at timestamptz,
  web_propose boolean,
  pending_count integer,
  failed_count integer,
  failed jsonb,
  to_fill_in jsonb
)
language plpgsql security definer set search_path = '' as $$
declare uid uuid; sid text; gate record; who text;
begin
  uid := auth.uid();
  if uid is null then return; end if;

  -- A token outlives its session once the owner signs out everywhere or disconnects the
  -- AI. Only a live row for the token's own session opens the door; a missing or
  -- malformed claim is refused the same way, never cast.
  sid := auth.jwt() ->> 'session_id';
  if sid is null or sid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return; end if;
  if not exists (
    select 1 from auth.sessions s
      where s.id = sid::uuid and s.user_id = uid and (s.not_after is null or s.not_after > now())
  ) then return; end if;

  -- What the old door said: the token's email, or the id when a token carries none.
  who := coalesce(auth.jwt() ->> 'email', uid::text);

  select * into gate from public.mcp_rate_bump(uid::text);
  if not gate.allowed then
    return query select false, gate.retry_after, who, null::jsonb, null::timestamptz, false, 0, 0, '[]'::jsonb, null::jsonb;
    return;
  end if;

  -- One row always, copy or not. The inbox counts unapplied rows: waiting ones apart from
  -- failed ones, and the newest twenty failures ride along with their reasons. The
  -- to_fill_in names are a few hundred bytes of the memory, carried whatever was asked.
  return query
    select true, gate.retry_after, who,
      case when p_with_memory then hm.memory end,
      hm.pushed_at,
      coalesce(hm.web_propose, false),
      case when p_with_memory then (
        select count(*)::integer from public.mcp_pending_writes p
          where p.user_id = uid and p.applied_at is null and p.failed_at is null
      ) else 0 end,
      case when p_with_memory then (
        select count(*)::integer from public.mcp_pending_writes p
          where p.user_id = uid and p.applied_at is null and p.failed_at is not null
      ) else 0 end,
      case when p_with_memory then (
        select coalesce(jsonb_agg(jsonb_build_object(
            'entry_id', f.id, 'kind', f.kind, 'reason', f.failure,
            'created_at', f.created_at, 'failed_at', f.failed_at, 'source_ref', f.source_ref)
            order by f.failed_at desc), '[]'::jsonb)
          from (select p.id, p.kind, p.failure, p.created_at, p.failed_at, p.source_ref
            from public.mcp_pending_writes p
            where p.user_id = uid and p.applied_at is null and p.failed_at is not null
            order by p.failed_at desc limit 20) f
      ) else '[]'::jsonb end,
      hm.memory -> 'to_fill_in'
    from (values (1)) me
      left join public.hosted_memories hm on hm.user_id = uid;
end $$;

revoke all on function public.mcp_memory_for_user(boolean) from public, anon, authenticated, service_role;
grant execute on function public.mcp_memory_for_user(boolean) to authenticated;
