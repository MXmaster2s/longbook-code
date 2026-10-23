-- Personal access tokens for the hosted MCP server: the OAuth fallback for clients
-- that cannot run a browser flow. The key itself is never stored — only its SHA-256.
-- Applied to the live project 2026-08-18.
create table public.access_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  key_hash text not null unique check (key_hash ~ '^[0-9a-f]{64}$'),
  scope text not null default 'read-only' check (scope = 'read-only'),
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);

alter table public.access_keys enable row level security;

create policy "a user sees only their own keys"
  on public.access_keys for select using (auth.uid() = user_id);
create policy "a user adds only their own keys"
  on public.access_keys for insert with check (auth.uid() = user_id);
create policy "a user revokes only their own keys"
  on public.access_keys for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "a user removes only their own keys"
  on public.access_keys for delete using (auth.uid() = user_id);

-- The function's door for key bearers: hash in, that owner's memory out. SECURITY
-- DEFINER so the anon-keyed function can redeem a key without any service role;
-- revoked or unknown hashes answer null, and every hit stamps last_used_at.
create or replace function public.mcp_memory_for_key(p_key_hash text)
returns table (key_id uuid, memory jsonb)
language plpgsql security definer set search_path = public as $$
declare k record;
begin
  select ak.id, ak.user_id into k
    from access_keys ak
    where ak.key_hash = p_key_hash and ak.revoked_at is null;
  if not found then return; end if;
  update access_keys set last_used_at = now() where id = k.id;
  return query select k.id, hm.memory from hosted_memories hm where hm.user_id = k.user_id;
  if not found then return query select k.id, null::jsonb; end if;
end $$;

revoke all on function public.mcp_memory_for_key(text) from public;
grant execute on function public.mcp_memory_for_key(text) to anon, authenticated;
