-- A second entrance to the same inbox, and the hardening the first one needed.
--
-- claude.ai's connector dialog takes a URL and an OAuth client — it has no field for a
-- key, so the propose door built for keys could never be reached from the surface the
-- owner actually uses. A signed-in session may now propose too, behind a switch that is
-- OFF until the owner turns it on, enforced here rather than in the tool list.

-- The switch. It rides on the hosted copy because that copy is what a signed-in AI reads:
-- no copy, nothing to propose against. An upsert of memory/pushed_at leaves it alone.
alter table public.hosted_memories
  add column web_propose boolean not null default false;

-- Which door a proposal came through, so the review can say so.
alter table public.mcp_pending_writes
  add column origin text not null default 'key' check (origin in ('key', 'oauth'));

-- How many unapplied proposals one owner may have waiting. An owner who stops opening
-- the app must not accumulate an unbounded queue, and an agent must be told plainly
-- rather than filing into a hole.
create or replace function public.mcp_pending_cap() returns integer
  language sql immutable as $$ select 100 $$;

-- The filing itself, once, for both doors. Reachable by nobody directly: the two
-- functions above name the owner, and this one trusts the owner it is given.
create or replace function public.mcp_file_proposal(
  p_user uuid,
  p_key uuid,
  p_origin text,
  p_kind text,
  p_payload jsonb,
  p_source_ref text,
  p_idempotency_key text
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

  -- The ceiling is checked only for a genuinely new proposal, so a retry of something
  -- already filed always succeeds even when the queue is full.
  if waiting >= mcp_pending_cap() then
    return query select null::uuid, false, waiting, 'queue_full';
    return;
  end if;

  begin
    insert into mcp_pending_writes (user_id, key_id, origin, kind, payload, source_ref, idempotency_key)
      values (p_user, p_key, p_origin, p_kind, p_payload, p_source_ref, p_idempotency_key)
      returning id into fresh;
  exception
    -- Two calls carrying one key can both miss the select above; the loser lands here
    -- and answers with the winner's row, which is what it would have wanted anyway.
    when unique_violation then
      select p.id into fresh from mcp_pending_writes p
        where p.user_id = p_user and p.idempotency_key = p_idempotency_key;
      return query select fresh, false, waiting, null::text;
      return;
    -- The table measures the payload in its own binary form, which the caller cannot
    -- predict from the text it sent. Refusing as "too large" is the truth; refusing as
    -- "try again in a moment" would loop forever.
    when check_violation then
      return query select null::uuid, false, waiting, 'payload_too_large';
      return;
  end;

  return query select fresh, true, waiting + 1, null::text;
end $$;

revoke all on function public.mcp_file_proposal(uuid, uuid, text, text, jsonb, text, text) from public, anon, authenticated, service_role;

-- The key door, recreated: the same contract, with the three faults the audit found —
-- a select-then-insert race, a payload cap that disagreed with the table's own check,
-- and no ceiling on the queue.
create or replace function public.mcp_propose_for_key(
  p_key_hash text,
  p_kind text,
  p_payload jsonb,
  p_source_ref text default null,
  p_idempotency_key text default null
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
    k.user_id, k.id, 'key', p_kind, p_payload, p_source_ref, p_idempotency_key
  );
end $$;

revoke all on function public.mcp_propose_for_key(text, text, jsonb, text, text) from public;
grant execute on function public.mcp_propose_for_key(text, text, jsonb, text, text) to anon, authenticated;

-- The signed-in door. The user comes from their own JWT, never from an argument, so no
-- caller can file into another owner's inbox. Refuses unless the owner turned the switch
-- on; refuses when there is no hosted copy, because then there is nothing to propose
-- against and an AI proposing blind is worse than one that stops.
create or replace function public.mcp_propose_for_user(
  p_kind text,
  p_payload jsonb,
  p_source_ref text default null,
  p_idempotency_key text default null
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
    uid, null::uuid, 'oauth', p_kind, p_payload, p_source_ref, p_idempotency_key
  );
end $$;

revoke all on function public.mcp_propose_for_user(text, jsonb, text, text) from public;
grant execute on function public.mcp_propose_for_user(text, jsonb, text, text) to authenticated;

-- The key door for reads, recreated too: expiry is now decided BEFORE the row is stamped
-- as used, and the answer carries the failed count as well as the waiting one — a
-- proposal that could not be applied must not be invisible to the agent that filed it.
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
  web_propose boolean,
  allowed boolean,
  retry_after integer,
  expired boolean
)
language plpgsql security definer set search_path = public as $$
declare k record; gate record; waiting integer; failed integer; switch boolean;
begin
  select ak.id, ak.user_id, ak.name, ak.scopes, ak.expires_at into k
    from access_keys ak
    where ak.key_hash = p_key_hash and ak.revoked_at is null;
  if not found then return; end if;

  if k.expires_at is not null and k.expires_at <= now() then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      0, 0, false, true, 0, true;
    return;
  end if;

  update access_keys set last_used_at = now() where id = k.id;

  select * into gate from mcp_rate_bump('key:' || k.id::text);
  if not gate.allowed then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      0, 0, false, false, gate.retry_after, false;
    return;
  end if;

  select count(*)::integer into waiting from mcp_pending_writes p
    where p.user_id = k.user_id and p.applied_at is null and p.failed_at is null;
  select count(*)::integer into failed from mcp_pending_writes p
    where p.user_id = k.user_id and p.failed_at is not null;
  select coalesce(hm.web_propose, false) into switch from hosted_memories hm where hm.user_id = k.user_id;

  return query
    select k.id, k.name, k.scopes, k.expires_at, hm.memory, hm.pushed_at,
      waiting, failed, coalesce(switch, false), true, gate.retry_after, false
    from hosted_memories hm where hm.user_id = k.user_id;
  if not found then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      waiting, failed, false, true, gate.retry_after, false;
  end if;
end $$;

revoke all on function public.mcp_memory_for_key(text) from public;
grant execute on function public.mcp_memory_for_key(text) to anon, authenticated;
