-- Sign in with Apple's server-to-server notices: Apple names the account by its own user id
-- (sub), and apple-account-events acts on the longbook account that signed in with it. Both
-- functions are the service role's alone.

-- The longbook account a Sign in with Apple user id belongs to, or null.
create or replace function public.apple_account_user(p_sub text)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select i.user_id from auth.identities i
    where i.provider = 'apple' and i.provider_id = p_sub
    limit 1
$$;

revoke all on function public.apple_account_user(text) from public, anon, authenticated;
grant execute on function public.apple_account_user(text) to service_role;

-- Ends every session of an account, a connected AI's included, as signing out everywhere
-- does: its refresh tokens go with it. Answers how many sessions ended.
create or replace function public.end_account_sessions(p_user uuid)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare ended integer;
begin
  delete from auth.refresh_tokens where user_id = p_user::text;
  with gone as (delete from auth.sessions where user_id = p_user returning 1)
  select count(*)::integer into ended from gone;
  return ended;
end $$;

revoke all on function public.end_account_sessions(uuid) from public, anon, authenticated;
grant execute on function public.end_account_sessions(uuid) to service_role;

-- When the person turned off Hide My Email forwarding to longbook; null while it forwards.
-- Mail to their relay address goes nowhere while it is set.
alter table public.profiles add column if not exists apple_relay_off_at timestamptz;
