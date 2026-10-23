-- Row-level security gates ROWS, not columns. Every policy here says "your own row" and
-- none of them ever said which columns — so a signed-in owner could PATCH any column of
-- any row they own. Most of that is harmless (their memory is theirs), but three things
-- were not, and Supabase's default grants had quietly re-opened a door a previous
-- migration meant to shut.
--
-- Verified before writing: entitlements and profiles carry a SELECT policy and no write
-- policy, so self-granting a licence or extending a trial already failed. The grants are
-- withdrawn anyway, so that a policy added later cannot become a breach on its own.

-- ---------------------------------------------------------------------------------------
-- access_keys — the sharp one. key_hash IS the credential: mcp_memory_for_key takes the
-- hash, not the key, and anon may call it. A client that can READ its own hash can hand
-- someone a permanent anonymous read; a client that can WRITE it can re-point an old,
-- innocent-looking key at a secret of their choosing. Neither is a thing the app does.

revoke select on table public.access_keys from anon, authenticated;
grant select (id, user_id, name, scopes, created_at, last_used_at, revoked_at, expires_at)
  on table public.access_keys to authenticated;

-- The app PATCHes exactly two columns: the name, and the revocation stamp. Nothing else
-- on this table has a client-side writer — scopes and expires_at are set at mint time,
-- and last_used_at belongs to the definer functions.
revoke update on table public.access_keys from anon, authenticated;
grant update (name, revoked_at) on table public.access_keys to authenticated;

revoke insert, delete on table public.access_keys from anon;

-- Revocation is the only kill switch this table has — there is no delete in the app — so
-- it may not be undone. A grant cannot express "one-way"; a trigger can.
create or replace function public.access_keys_revocation_is_final()
returns trigger language plpgsql as $$
begin
  if old.revoked_at is not null and new.revoked_at is null then
    raise exception 'a revoked key stays revoked — make a new one instead'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

drop trigger if exists access_keys_revocation_is_final on public.access_keys;
create trigger access_keys_revocation_is_final
  before update on public.access_keys
  for each row execute function public.access_keys_revocation_is_final();

-- ---------------------------------------------------------------------------------------
-- The two tables that hold claims the APP makes about a user, which it later trusts.
-- Written only by the Polar webhook and the sign-up trigger, both service-role or definer.

revoke insert, update, delete on table public.entitlements from anon, authenticated;
revoke select on table public.entitlements from anon;

revoke insert, update, delete on table public.profiles from anon, authenticated;
revoke select on table public.profiles from anon;

-- ---------------------------------------------------------------------------------------
-- Sharing — no client ever touches these; the share-report function holds service_role.
-- Closed today only by the absence of a policy, which is one accident deep. The grants
-- carried SELECT on password_hash and password_salt.

revoke all on table public.shared_reports from anon, authenticated;
revoke all on table public.report_comments from anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- The proposal inbox. Rows arrive only through mcp_file_proposal; the app stamps the
-- outcome and nothing else. Leaving payload, kind and origin writable let an owner
-- rewrite a filed suggestion — self-deception rather than escalation, but the review
-- screen's attribution should mean what it says.

revoke update on table public.mcp_pending_writes from anon, authenticated;
grant update (applied_at, failed_at, failure) on table public.mcp_pending_writes to authenticated;
revoke insert on table public.mcp_pending_writes from anon, authenticated;
revoke select, delete on table public.mcp_pending_writes from anon;

-- ---------------------------------------------------------------------------------------
-- The owner's own material: their memory and their tag vocabulary. Every column here is
-- theirs to set, and the app writes them directly — no column narrowing, on purpose.
-- anon holds grants it can never use (no policy names it); withdrawn all the same.

revoke all on table public.hosted_memories from anon;
revoke all on table public.structures from anon;

-- ---------------------------------------------------------------------------------------
-- Functions. Supabase grants EXECUTE on every new function to anon and authenticated by
-- name, so a migration that revokes from PUBLIC alone leaves both holding it — the exact
-- gap 20260819171000_mcp_rate_grants.sql exists to close for mcp_rate_bump, which was
-- not carried to the functions written after it.
--
-- waitlist_rate_bump is the live one: SECURITY DEFINER, writing a caller-supplied subject
-- into a table anon cannot otherwise reach, deciding its own limit from a caller-supplied
-- argument. Reachable with nothing but the publishable key.

revoke all on function public.waitlist_rate_bump(text, integer) from anon, authenticated;

-- Inert — neither is callable through PostgREST, both return trigger types — but the
-- grant is the same mistake and should not sit there looking deliberate.
revoke all on function public.handle_new_user() from anon, authenticated;
revoke all on function public.rls_auto_enable() from anon, authenticated;

-- Only a signed-in caller can propose as themselves; auth.uid() is null for anon anyway.
revoke all on function public.mcp_propose_for_user(text, jsonb, text, text) from anon;
revoke all on function public.mcp_pending_cap() from anon, authenticated;

-- Left alone deliberately: mcp_memory_for_key and mcp_propose_for_key keep EXECUTE for
-- anon, because the hosted MCP function redeems keys with the publishable key and no
-- session. They take a key hash and answer for that key's owner only.

-- ---------------------------------------------------------------------------------------
-- The same trap once more, one layer down. Postgres itself grants EXECUTE on every new
-- function to PUBLIC, which anon and authenticated inherit — so revoking from the two
-- roles by name leaves the door open. Both revokes are needed, always.

revoke all on function public.handle_new_user() from public;
revoke all on function public.rls_auto_enable() from public;
revoke all on function public.mcp_pending_cap() from public;
revoke all on function public.access_keys_revocation_is_final() from public, anon, authenticated;

-- REFERENCES on the credential column is a leftover of the table-level grant. INSERT
-- stays: minting a key is the one legitimate client write of a hash, and it is write-only.
revoke references (key_hash) on table public.access_keys from anon, authenticated;
