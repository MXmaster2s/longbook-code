-- The signed-in door, recreated with one more column: the hints setup kept (people by role,
-- accounts by kind) ride along with the to_fill_in names, so a handshake that leaves the
-- memory behind still says them. A function deployed before this column reads it as absent.
drop function if exists public.mcp_memory_for_user(boolean);

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
  to_fill_in jsonb,
  cloud boolean,
  hints jsonb
)
language plpgsql security definer set search_path = '' as $$
declare uid uuid; sid text; gate record; who text;
begin
  uid := auth.uid();
  if uid is null then return; end if;

  sid := auth.jwt() ->> 'session_id';
  if sid is null or sid !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return; end if;
  if not exists (
    select 1 from auth.sessions s
      where s.id = sid::uuid and s.user_id = uid and (s.not_after is null or s.not_after > now())
  ) then return; end if;

  who := coalesce(auth.jwt() ->> 'email', uid::text);

  select * into gate from public.mcp_rate_bump(uid::text);
  if not gate.allowed then
    return query select false, gate.retry_after, who, null::jsonb, null::timestamptz, false, 0, 0, '[]'::jsonb, null::jsonb, null::boolean, null::jsonb;
    return;
  end if;

  if not public.has_cloud(uid) then
    return query select true, gate.retry_after, who, null::jsonb, null::timestamptz, false, 0, 0, '[]'::jsonb, null::jsonb, false, null::jsonb;
    return;
  end if;

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
      hm.memory -> 'to_fill_in',
      true,
      hm.memory -> 'hints'
    from (values (1)) me
      left join public.hosted_memories hm on hm.user_id = uid;
end $$;

revoke all on function public.mcp_memory_for_user(boolean) from public, anon, authenticated, service_role;
grant execute on function public.mcp_memory_for_user(boolean) to authenticated;
