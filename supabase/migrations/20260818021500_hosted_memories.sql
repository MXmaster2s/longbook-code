-- The hosted copy of a financial memory: one row per user, pushed by the user's own
-- app on an explicit opt-in, read back by the hosted MCP server with the user's JWT.
-- Revoke is a row delete.
create table public.hosted_memories (
  user_id uuid primary key references auth.users (id) on delete cascade,
  memory jsonb not null,
  pushed_at timestamptz not null default now(),
  -- A memory is a ledger of commitments, not a document store; 2 MB is far past any
  -- honest vault and refuses a runaway payload before it becomes a bill.
  constraint hosted_memory_bounded check (pg_column_size(memory) <= 2097152)
);

alter table public.hosted_memories enable row level security;

-- The owner's JWT is the only door: the app pushes and revokes with it, the hosted
-- MCP server reads with it. No service-role path exists for this table.
create policy "a user reads only their own memory"
  on public.hosted_memories for select to authenticated
  using (auth.uid() = user_id);

create policy "a user pushes only their own memory"
  on public.hosted_memories for insert to authenticated
  with check (auth.uid() = user_id);

create policy "a user replaces only their own memory"
  on public.hosted_memories for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "a user revokes only their own memory"
  on public.hosted_memories for delete to authenticated
  using (auth.uid() = user_id);
