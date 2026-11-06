-- A proposal the app could not apply is visible to the agent that filed it, with its
-- reason, on both doors; and a corrected proposal filed under the same key replaces the
-- failed row instead of being swallowed as "already filed".

-- The filing, recreated in place: the same signature, so the two door functions that
-- call it by name keep working. A key that names a FAILED row re-files it — the payload
-- is replaced, the failure cleared, and the row waits again as new.
create or replace function public.mcp_file_proposal(
  p_user uuid,
  p_key uuid,
  p_origin text,
  p_kind text,
  p_payload jsonb,
  p_source_ref text,
  p_idempotency_key text,
  p_client text default null
)
returns table (entry_id uuid, created boolean, pending_count integer, error text)
language plpgsql security definer set search_path = public as $$
declare existing uuid; existing_failed timestamptz; fresh uuid; waiting integer;
begin
  select count(*)::integer into waiting from mcp_pending_writes p
    where p.user_id = p_user and p.applied_at is null and p.failed_at is null;

  if p_idempotency_key is not null then
    select p.id, p.failed_at into existing, existing_failed from mcp_pending_writes p
      where p.user_id = p_user and p.idempotency_key = p_idempotency_key;
    if found and existing_failed is null then
      return query select existing, false, waiting, null::text;
      return;
    end if;
  end if;

  if waiting >= mcp_pending_cap() then
    return query select null::uuid, false, waiting, 'queue_full';
    return;
  end if;

  begin
    if existing is not null then
      update mcp_pending_writes set
        key_id = p_key, origin = p_origin, kind = p_kind, payload = p_payload,
        source_ref = p_source_ref, client = nullif(left(p_client, 60), ''),
        created_at = now(), failed_at = null, failure = null
        where id = existing;
      fresh := existing;
    else
      insert into mcp_pending_writes (user_id, key_id, origin, kind, payload, source_ref, idempotency_key, client)
        values (p_user, p_key, p_origin, p_kind, p_payload, p_source_ref, p_idempotency_key, nullif(left(p_client, 60), ''))
        returning id into fresh;
    end if;
  exception
    when unique_violation then
      select p.id into fresh from mcp_pending_writes p
        where p.user_id = p_user and p.idempotency_key = p_idempotency_key;
      return query select fresh, false, waiting, null::text;
      return;
    when check_violation then
      return query select null::uuid, false, waiting, 'payload_too_large';
      return;
  end;

  return query select fresh, true, waiting + 1, null::text;
end $$;

revoke all on function public.mcp_file_proposal(uuid, uuid, text, text, jsonb, text, text, text) from public, anon, authenticated, service_role;

-- The key door for reads, recreated: the answer now carries the newest twenty failed
-- proposals with their reasons beside the counts, so one redemption tells a keyed
-- agent what it got wrong.
drop function public.mcp_memory_for_key(text);

create function public.mcp_memory_for_key(p_key_hash text)
returns table (
  key_id uuid,
  key_name text,
  scopes text[],
  expires_at timestamptz,
  memory jsonb,
  pushed_at timestamptz,
  pending_count integer,
  failed_count integer,
  failed jsonb,
  web_propose boolean,
  allowed boolean,
  retry_after integer,
  expired boolean
)
language plpgsql security definer set search_path = public as $$
declare k record; gate record; waiting_n integer; failed_n integer; failed_rows jsonb; switch boolean;
begin
  select ak.id, ak.user_id, ak.name, ak.scopes, ak.expires_at into k
    from access_keys ak
    where ak.key_hash = p_key_hash and ak.revoked_at is null;
  if not found then return; end if;

  if k.expires_at is not null and k.expires_at <= now() then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      0, 0, '[]'::jsonb, false, true, 0, true;
    return;
  end if;

  update access_keys set last_used_at = now() where id = k.id;

  select * into gate from mcp_rate_bump('key:' || k.id::text);
  if not gate.allowed then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      0, 0, '[]'::jsonb, false, false, gate.retry_after, false;
    return;
  end if;

  select count(*)::integer into waiting_n from mcp_pending_writes p
    where p.user_id = k.user_id and p.applied_at is null and p.failed_at is null;
  select count(*)::integer into failed_n from mcp_pending_writes p
    where p.user_id = k.user_id and p.failed_at is not null;
  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_id', f.id, 'kind', f.kind, 'reason', f.failure,
      'created_at', f.created_at, 'failed_at', f.failed_at, 'source_ref', f.source_ref)
      order by f.failed_at desc), '[]'::jsonb)
    into failed_rows
    from (select p.id, p.kind, p.failure, p.created_at, p.failed_at, p.source_ref
      from mcp_pending_writes p
      where p.user_id = k.user_id and p.failed_at is not null
      order by p.failed_at desc limit 20) f;
  select coalesce(hm.web_propose, false) into switch from hosted_memories hm where hm.user_id = k.user_id;

  return query
    select k.id, k.name, k.scopes, k.expires_at, hm.memory, hm.pushed_at,
      waiting_n, failed_n, failed_rows, coalesce(switch, false), true, gate.retry_after, false
    from hosted_memories hm where hm.user_id = k.user_id;
  if not found then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      waiting_n, failed_n, failed_rows, false, true, gate.retry_after, false;
  end if;
end $$;

revoke all on function public.mcp_memory_for_key(text) from public;
grant execute on function public.mcp_memory_for_key(text) to anon, authenticated;
