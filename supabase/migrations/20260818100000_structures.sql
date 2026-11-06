-- The structure store: each user's tag definitions — kind, name, icon, template — and
-- NEVER their values. No commitment names, no amounts, no dates, no notes reach this
-- table; the app's payload guard test enforces that boundary at build time. Longbook
-- learns from these definitions in aggregate to grow the shipped library.
create table public.structures (
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('commitment', 'member', 'account')),
  name_key text not null,
  name text not null,
  icon text,
  template jsonb,
  source text not null default 'user' check (source in ('library', 'user', 'ai')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, name_key)
);

alter table public.structures enable row level security;

-- Owner-only in every direction, same stance as hosted_memories: the client writes its
-- own row under its own JWT, and nobody's structures are readable by anyone else.
create policy "a user reads only their own structures"
  on public.structures for select using (auth.uid() = user_id);

create policy "a user adds only their own structures"
  on public.structures for insert with check (auth.uid() = user_id);

create policy "a user updates only their own structures"
  on public.structures for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "a user removes only their own structures"
  on public.structures for delete using (auth.uid() = user_id);
