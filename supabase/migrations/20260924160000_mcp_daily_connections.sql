-- Connections beside the calls: one per initialize message, the start of a session, counted
-- per UTC day and AI application like the two counts already there. Still no identifier.
alter table public.mcp_daily_counts
  add column connections bigint not null default 0 check (connections >= 0);

-- The count takes a fifth argument with a default, so a caller that sends four still lands
-- here. The four-argument version goes first: two would make a four-argument call ambiguous.
drop function public.mcp_count(text, text, integer, integer);

create function public.mcp_count(p_key_hash text, p_client text, p_calls integer, p_edits integer, p_connections integer default 0)
returns void
language plpgsql security definer set search_path = public as $$
declare
  n_calls integer := least(greatest(coalesce(p_calls, 0), 0), 100);
  n_edits integer := least(greatest(coalesce(p_edits, 0), 0), 100);
  n_connections integer := least(greatest(coalesce(p_connections, 0), 0), 100);
  v_today date := (now() at time zone 'utc')::date;
  v_client text := left(btrim(regexp_replace(coalesce(p_client, ''), '[^A-Za-z0-9._ -]', '', 'g')), 40);
begin
  if n_calls = 0 and n_edits = 0 and n_connections = 0 then return; end if;
  if v_client = '' then v_client := 'other'; end if;

  if auth.uid() is null and not exists (
    select 1 from access_keys ak
      where ak.key_hash = p_key_hash
        and ak.revoked_at is null
        and (ak.expires_at is null or ak.expires_at > now())
  ) then
    return;
  end if;

  if not exists (select 1 from mcp_daily_counts where day = v_today and client = v_client)
     and (select count(*) from mcp_daily_counts where day = v_today) >= 50 then
    v_client := 'other';
  end if;

  insert into mcp_daily_counts as c (day, client, calls, edits, connections)
    values (v_today, v_client, n_calls, n_edits, n_connections)
    on conflict (day, client) do update set
      calls = c.calls + excluded.calls,
      edits = c.edits + excluded.edits,
      connections = c.connections + excluded.connections;
end $$;

revoke all on function public.mcp_count(text, text, integer, integer, integer) from public;
revoke all on function public.mcp_count(text, text, integer, integer, integer) from anon, authenticated;
grant execute on function public.mcp_count(text, text, integer, integer, integer) to anon, authenticated;
