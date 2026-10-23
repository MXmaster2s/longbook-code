-- The ledger's one write, as an increment in the database rather than a read and a
-- write from the function: pieces of one statement are read side by side now, and two
-- answers landing together must both count. Service role only; no client may call it.
create function public.statement_import_spend(p_user uuid, p_import text, p_tokens integer)
returns void
language sql
security definer
set search_path = public
as $$
  update public.statement_imports
     set calls = calls + 1,
         tokens = tokens + greatest(p_tokens, 0),
         last_call_at = now()
   where user_id = p_user and import_id = p_import;
$$;

revoke all on function public.statement_import_spend(uuid, text, integer) from public, anon, authenticated;
