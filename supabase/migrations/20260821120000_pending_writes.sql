-- Hosted writes, as proposals. Nothing from the cloud rewrites the memory: a keyed
-- agent files a proposal here, and the owner's own app applies it through the same
-- outside-change door any editor uses, so it lands in Changes to keep or undo. The
-- folder stays the truth.

-- Keys gain a scope vocabulary. 'read-only' was the single allowed value; the array
-- keeps that meaning as memory:read and adds memory:propose. Never memory:write.
alter table public.access_keys
  add column scopes text[] not null default array['memory:read'],
  add column expires_at timestamptz;

-- Every key that exists is read-only, so the old single-value column has said all it
-- can; scopes replaces it outright rather than leaving two answers to one question.
alter table public.access_keys drop constraint if exists access_keys_scope_check;
alter table public.access_keys drop column scope;

alter table public.access_keys
  add constraint access_keys_scopes_known check (
    array_length(scopes, 1) between 1 and 2
    and scopes <@ array['memory:read', 'memory:propose']
    and 'memory:read' = any (scopes)
  );

-- The inbox. One row per proposed write, applied once by the first app that sees it.
create table public.mcp_pending_writes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  key_id uuid references public.access_keys (id) on delete set null,
  -- The write tool this proposes: add_commitments, update_commitment, mark_paid,
  -- cancel_commitment, write_report, leave_insight. Validated by the function, not here,
  -- so a new tool does not need a migration.
  kind text not null check (char_length(kind) between 1 and 40),
  payload jsonb not null,
  -- Where it came from — "gmail:18c2…", "documents/hdfc-2026.pdf" — carried into the
  -- row's _provenance.source when the app applies it.
  source_ref text check (source_ref is null or char_length(source_ref) between 1 and 200),
  -- The agent's own key for this intended write. Unique per user, so a retried cron
  -- answers already_exists instead of proposing the gym twice.
  idempotency_key text check (idempotency_key is null or char_length(idempotency_key) between 1 and 200),
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  -- Set when the app could not apply it: the reason, in the product's voice.
  failed_at timestamptz,
  failure text,
  -- A proposal is a ledger edit, not a document store; 256 KB matches the servers' cap.
  constraint pending_payload_bounded check (pg_column_size(payload) <= 262144)
);

create unique index mcp_pending_idempotent
  on public.mcp_pending_writes (user_id, idempotency_key)
  where idempotency_key is not null;

create index mcp_pending_waiting
  on public.mcp_pending_writes (user_id, created_at)
  where applied_at is null and failed_at is null;

alter table public.mcp_pending_writes enable row level security;

-- The owner's JWT is the only ordinary door: their app lists what is waiting and stamps
-- each one applied. Inserting is not among the policies — proposals arrive only through
-- the definer function below, which names the key that made them.
create policy "a user sees only their own pending writes"
  on public.mcp_pending_writes for select to authenticated
  using (auth.uid() = user_id);

create policy "a user stamps only their own pending writes"
  on public.mcp_pending_writes for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "a user clears only their own pending writes"
  on public.mcp_pending_writes for delete to authenticated
  using (auth.uid() = user_id);

-- The key door for reads, recreated: the return shape grows the key's identity and scopes
-- so one redemption answers whoami as well as a memory read. No service role, no JWT.
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
  allowed boolean,
  retry_after integer,
  expired boolean
)
language plpgsql security definer set search_path = public as $$
declare k record; gate record;
begin
  select ak.id, ak.user_id, ak.name, ak.scopes, ak.expires_at into k
    from access_keys ak
    where ak.key_hash = p_key_hash and ak.revoked_at is null;
  if not found then return; end if;
  update access_keys set last_used_at = now() where id = k.id;

  -- An expired key answers with its identity and nothing else, so the caller can say
  -- WHY it stopped working instead of "unauthorized".
  if k.expires_at is not null and k.expires_at <= now() then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz, 0, true, 0, true;
    return;
  end if;

  select * into gate from mcp_rate_bump('key:' || k.id::text);
  if not gate.allowed then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz, 0, false, gate.retry_after, false;
    return;
  end if;

  return query
    select k.id, k.name, k.scopes, k.expires_at, hm.memory, hm.pushed_at,
      (select count(*)::integer from mcp_pending_writes p
        where p.user_id = k.user_id and p.applied_at is null and p.failed_at is null),
      true, gate.retry_after, false
    from hosted_memories hm where hm.user_id = k.user_id;
  if not found then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      (select count(*)::integer from mcp_pending_writes p
        where p.user_id = k.user_id and p.applied_at is null and p.failed_at is null),
      true, gate.retry_after, false;
  end if;
end $$;

revoke all on function public.mcp_memory_for_key(text) from public;
grant execute on function public.mcp_memory_for_key(text) to anon, authenticated;

-- The proposal door. The key names the user; no caller ever passes a user_id. Requires
-- memory:propose; an idempotent repeat answers the existing row's id with created false.
create function public.mcp_propose_for_key(
  p_key_hash text,
  p_kind text,
  p_payload jsonb,
  p_source_ref text default null,
  p_idempotency_key text default null
)
returns table (entry_id uuid, created boolean, pending_count integer, error text)
language plpgsql security definer set search_path = public as $$
declare k record; existing uuid; fresh uuid;
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

  if p_idempotency_key is not null then
    select p.id into existing from mcp_pending_writes p
      where p.user_id = k.user_id and p.idempotency_key = p_idempotency_key;
    if found then
      return query select existing, false,
        (select count(*)::integer from mcp_pending_writes p
          where p.user_id = k.user_id and p.applied_at is null and p.failed_at is null),
        null::text;
      return;
    end if;
  end if;

  insert into mcp_pending_writes (user_id, key_id, kind, payload, source_ref, idempotency_key)
    values (k.user_id, k.id, p_kind, p_payload, p_source_ref, p_idempotency_key)
    returning id into fresh;

  return query select fresh, true,
    (select count(*)::integer from mcp_pending_writes p
      where p.user_id = k.user_id and p.applied_at is null and p.failed_at is null),
    null::text;
end $$;

revoke all on function public.mcp_propose_for_key(text, text, jsonb, text, text) from public;
grant execute on function public.mcp_propose_for_key(text, text, jsonb, text, text) to anon, authenticated;
