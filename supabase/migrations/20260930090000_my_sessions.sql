-- The sessions of one account, for the sign-out screen: when each began, when it was last
-- used, the user agent it signed in with, and the connector's name when an AI holds it.
-- The newest 50 come back, with the total. The IP address stays where it is. Only the
-- server-side function reads this, with the service role, and only for the id in the
-- caller's own token.
create or replace function public.my_sessions(p_user uuid)
returns table (
  id uuid,
  created_at timestamptz,
  last_active timestamptz,
  user_agent text,
  is_connector boolean,
  client_name text,
  total bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id,
         s.created_at,
         coalesce(s.refreshed_at at time zone 'UTC', s.updated_at, s.created_at) as last_active,
         s.user_agent,
         s.oauth_client_id is not null as is_connector,
         c.client_name,
         count(*) over () as total
  from auth.sessions s
  left join auth.oauth_clients c on c.id = s.oauth_client_id and c.deleted_at is null
  where s.user_id = p_user
    and (s.not_after is null or s.not_after > now())
  order by 3 desc
  limit 50;
$$;

revoke all on function public.my_sessions(uuid) from public, anon, authenticated;
grant execute on function public.my_sessions(uuid) to service_role;
