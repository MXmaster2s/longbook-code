-- longbook Cloud: a monthly App Store subscription that every use of longbook's server
-- needs. The app licence stays a one-time purchase in entitlements. One rule, has_cloud,
-- is asked by the hosted copy, the MCP doors, the server functions and the nightly expiry.

-- One row per account, written by apple-purchase and apple-notifications with the service
-- role. In the grace period expires_at holds the grace period's end, so one comparison
-- serves both statuses. A client reads status, expires_at and auto_renew of its own row.
create table if not exists public.cloud_subscriptions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  product_id text not null,
  apple_original_transaction_id text not null unique,
  apple_environment text not null check (apple_environment in ('Sandbox', 'Production')),
  app_account_token uuid,
  status text not null check (status in ('active', 'grace', 'billing_retry', 'expired', 'revoked')),
  expires_at timestamptz,
  auto_renew boolean not null default true,
  last_signed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.cloud_subscriptions enable row level security;

drop policy if exists "a user reads only their own Cloud subscription" on public.cloud_subscriptions;
create policy "a user reads only their own Cloud subscription"
  on public.cloud_subscriptions for select to authenticated
  using (auth.uid() = user_id);

-- Named columns, as entitlements grants them: the Apple ids and the token stay the server's.
revoke all on table public.cloud_subscriptions from public, anon, authenticated;
grant select (user_id, status, expires_at, auto_renew) on table public.cloud_subscriptions to authenticated;

-- Cloud granted by hand, the way statement_allowances grants imports: one account, until a
-- date, with a note. Service role only; no client may see or touch it.
create table if not exists public.cloud_grants (
  user_id uuid primary key references auth.users (id) on delete cascade,
  until timestamptz not null,
  note text,
  granted_at timestamptz not null default now()
);

alter table public.cloud_grants enable row level security;
revoke all on table public.cloud_grants from public, anon, authenticated;

-- When an account's Cloud runs out: the latest of its trial's end, its subscription's
-- expiry while active or in grace, and any hand-made grant. Null for no account.
-- Reachable only through has_cloud and the nightly expiry.
create or replace function public.cloud_until(uid uuid)
returns timestamptz
language sql stable security definer set search_path = ''
as $$
  select greatest(
    (select p.trial_started_at + interval '14 days' from public.profiles p where p.id = uid),
    (select s.expires_at from public.cloud_subscriptions s
       where s.user_id = uid and s.status in ('active', 'grace')),
    (select g.until from public.cloud_grants g where g.user_id = uid)
  )
$$;

revoke all on function public.cloud_until(uuid) from public, anon, authenticated, service_role;

-- The one rule everything gates on. A signed-in caller is answered for its own account
-- alone; a server-side caller, whose token names no subject, for any account.
create or replace function public.has_cloud(uid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select (auth.uid() is null or auth.uid() = uid)
    and coalesce(public.cloud_until(uid) > now(), false)
$$;

revoke all on function public.has_cloud(uuid) from public, anon;
grant execute on function public.has_cloud(uuid) to authenticated, service_role;

-- The same answer for the app, about the account its token names.
create or replace function public.has_cloud()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select public.has_cloud(auth.uid())
$$;

revoke all on function public.has_cloud() from public, anon;
grant execute on function public.has_cloud() to authenticated;

-- The hosted copy is pushed and refreshed only while the account has Cloud. Reading it
-- back and revoking it stay open, so a lapsed account can still take its copy down.
drop policy if exists "a user pushes only their own memory" on public.hosted_memories;
create policy "a user pushes only their own memory"
  on public.hosted_memories for insert to authenticated
  with check (auth.uid() = user_id and public.has_cloud(user_id));

drop policy if exists "a user replaces only their own memory" on public.hosted_memories;
create policy "a user replaces only their own memory"
  on public.hosted_memories for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and public.has_cloud(user_id));

-- The filing, recreated in place: a proposal for an account without Cloud is refused as
-- entitlement_required before anything else is read. Both doors call it by name.
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
  if not has_cloud(p_user) then
    return query select null::uuid, false, 0, 'entitlement_required';
    return;
  end if;

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

-- The key door for reads, recreated: the answer gains a cloud column. An account without
-- Cloud is answered with its key's identity and no memory, and cloud false says why.
drop function if exists public.mcp_memory_for_key(text);

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
  expired boolean,
  cloud boolean
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
      0, 0, '[]'::jsonb, false, true, 0, true, null::boolean;
    return;
  end if;

  update access_keys set last_used_at = now() where id = k.id;

  select * into gate from mcp_rate_bump('key:' || k.id::text);
  if not gate.allowed then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      0, 0, '[]'::jsonb, false, false, gate.retry_after, false, null::boolean;
    return;
  end if;

  if not has_cloud(k.user_id) then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      0, 0, '[]'::jsonb, false, true, gate.retry_after, false, false;
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
      waiting_n, failed_n, failed_rows, coalesce(switch, false), true, gate.retry_after, false, true
    from hosted_memories hm where hm.user_id = k.user_id;
  if not found then
    return query select k.id, k.name, k.scopes, k.expires_at, null::jsonb, null::timestamptz,
      waiting_n, failed_n, failed_rows, false, true, gate.retry_after, false, true;
  end if;
end $$;

revoke all on function public.mcp_memory_for_key(text) from public;
grant execute on function public.mcp_memory_for_key(text) to anon, authenticated;

-- The signed-in door, recreated with the same cloud column: a live session without Cloud
-- is let through the handshake with no memory, and cloud false says why.
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
  cloud boolean
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
    return query select false, gate.retry_after, who, null::jsonb, null::timestamptz, false, 0, 0, '[]'::jsonb, null::jsonb, null::boolean;
    return;
  end if;

  if not public.has_cloud(uid) then
    return query select true, gate.retry_after, who, null::jsonb, null::timestamptz, false, 0, 0, '[]'::jsonb, null::jsonb, false;
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
      true
    from (values (1)) me
      left join public.hosted_memories hm on hm.user_id = uid;
end $$;

revoke all on function public.mcp_memory_for_user(boolean) from public, anon, authenticated, service_role;
grant execute on function public.mcp_memory_for_user(boolean) to authenticated;

-- The nightly expiry, recreated: a copy also goes once its owner has been without Cloud
-- for thirty days, by the rule has_cloud reads. Proposals keep their ninety days.
create or replace function public.expire_hosted_copies()
returns table (copies integer, proposals integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  gone_copies integer;
  gone_proposals integer;
begin
  with gone as (
    delete from hosted_memories hm
      where hm.pushed_at < now() - interval '90 days'
         or cloud_until(hm.user_id) < now() - interval '30 days'
      returning 1
  )
  select count(*) into gone_copies from gone;
  with gone as (
    delete from mcp_pending_writes where created_at < now() - interval '90 days' returning 1
  )
  select count(*) into gone_proposals from gone;
  return query select gone_copies, gone_proposals;
end;
$$;

revoke all on function public.expire_hosted_copies() from public, anon, authenticated;
