-- A proposal remembers the AI that filed it, as its requests introduced it, so the
-- app signs rows "Claude" rather than "web session". Both doors pass it; unknown is null.

alter table public.mcp_pending_writes
  add column if not exists client text
  check (client is null or char_length(client) between 1 and 60);

drop function if exists public.mcp_propose_for_user(text, jsonb, text, text);
drop function if exists public.mcp_propose_for_key(text, text, jsonb, text, text);
drop function if exists public.mcp_file_proposal(uuid, uuid, text, text, jsonb, text, text);

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
declare existing uuid; fresh uuid; waiting integer;
begin
  select count(*)::integer into waiting from mcp_pending_writes p
    where p.user_id = p_user and p.applied_at is null and p.failed_at is null;

  if p_idempotency_key is not null then
    select p.id into existing from mcp_pending_writes p
      where p.user_id = p_user and p.idempotency_key = p_idempotency_key;
    if found then
      return query select existing, false, waiting, null::text;
      return;
    end if;
  end if;

  if waiting >= mcp_pending_cap() then
    return query select null::uuid, false, waiting, 'queue_full';
    return;
  end if;

  begin
    insert into mcp_pending_writes (user_id, key_id, origin, kind, payload, source_ref, idempotency_key, client)
      values (p_user, p_key, p_origin, p_kind, p_payload, p_source_ref, p_idempotency_key, nullif(left(p_client, 60), ''))
      returning id into fresh;
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

create or replace function public.mcp_propose_for_key(
  p_key_hash text,
  p_kind text,
  p_payload jsonb,
  p_source_ref text default null,
  p_idempotency_key text default null,
  p_client text default null
)
returns table (entry_id uuid, created boolean, pending_count integer, error text)
language plpgsql security definer set search_path = public as $$
declare k record;
begin
  select ak.id, ak.user_id, ak.scopes, ak.expires_at into k
    from access_keys ak
    where ak.key_hash = p_key_hash and ak.revoked_at is null;
  if not found then
    return query select null::uuid, false, 0, 'key_revoked';
    return;
  end if;
  if k.expires_at is not null and k.expires_at <= now() then
    return query select null::uuid, false, 0, 'key_expired';
    return;
  end if;
  if not ('memory:propose' = any (k.scopes)) then
    return query select null::uuid, false, 0, 'insufficient_scope';
    return;
  end if;
  update access_keys set last_used_at = now() where id = k.id;

  return query select * from mcp_file_proposal(
    k.user_id, k.id, 'key', p_kind, p_payload, p_source_ref, p_idempotency_key, p_client
  );
end $$;

revoke all on function public.mcp_propose_for_key(text, text, jsonb, text, text, text) from public;
grant execute on function public.mcp_propose_for_key(text, text, jsonb, text, text, text) to anon, authenticated;

create or replace function public.mcp_propose_for_user(
  p_kind text,
  p_payload jsonb,
  p_source_ref text default null,
  p_idempotency_key text default null,
  p_client text default null
)
returns table (entry_id uuid, created boolean, pending_count integer, error text)
language plpgsql security definer set search_path = public as $$
declare uid uuid; allowed boolean;
begin
  uid := auth.uid();
  if uid is null then
    return query select null::uuid, false, 0, 'unauthorized';
    return;
  end if;
  select hm.web_propose into allowed from hosted_memories hm where hm.user_id = uid;
  if not found then
    return query select null::uuid, false, 0, 'not_found';
    return;
  end if;
  if not coalesce(allowed, false) then
    return query select null::uuid, false, 0, 'insufficient_scope';
    return;
  end if;

  return query select * from mcp_file_proposal(
    uid, null::uuid, 'oauth', p_kind, p_payload, p_source_ref, p_idempotency_key, p_client
  );
end $$;

revoke all on function public.mcp_propose_for_user(text, jsonb, text, text, text) from public;
grant execute on function public.mcp_propose_for_user(text, jsonb, text, text, text) to authenticated;
