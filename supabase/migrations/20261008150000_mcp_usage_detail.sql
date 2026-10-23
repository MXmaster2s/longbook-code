-- Two more daily counts for the hosted MCP server, and a tidy for the job log. Still no
-- identifier: no account, key, address or authorization id is stored, only names and counts.
--
-- mcp_daily_surfaces: connections per UTC day, AI application (its user agent, as
-- mcp_daily_counts has it), door (oauth for a signed-in connection, key for an access key)
-- and surface (the name the client gives itself in initialize's clientInfo).
-- mcp_daily_tools: tool calls per UTC day, AI application, door and tool name.
create table public.mcp_daily_surfaces (
  day date not null default (now() at time zone 'utc')::date,
  client text not null,
  door text not null check (door in ('oauth', 'key')),
  surface text not null,
  connections bigint not null default 0 check (connections >= 0),
  primary key (day, client, door, surface)
);

create table public.mcp_daily_tools (
  day date not null default (now() at time zone 'utc')::date,
  client text not null,
  door text not null check (door in ('oauth', 'key')),
  tool text not null,
  calls bigint not null default 0 check (calls >= 0),
  primary key (day, client, door, tool)
);

-- No policies on purpose, as with mcp_daily_counts: only mcp_count_detail writes here.
alter table public.mcp_daily_surfaces enable row level security;
alter table public.mcp_daily_tools enable row level security;
revoke all on table public.mcp_daily_surfaces, public.mcp_daily_tools from public, anon, authenticated;
revoke truncate, trigger, references on table public.mcp_daily_surfaces, public.mcp_daily_tools from public, anon, authenticated;

-- Adds one request's connections and tool calls. Counts only a real caller, like mcp_count.
-- Labels are cleaned and capped at 40 characters; past fifty a day a new surface or tool counts
-- as other; at most 100 per number and 20 tool names per call.
create function public.mcp_count_detail(p_key_hash text, p_client text, p_door text, p_surface text,
                                        p_connections integer, p_tools jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_today date := (now() at time zone 'utc')::date;
  v_client text := left(btrim(regexp_replace(coalesce(p_client, ''), '[^A-Za-z0-9._ -]', '', 'g')), 40);
  v_surface text := left(btrim(regexp_replace(coalesce(p_surface, ''), '[^A-Za-z0-9._ -]', '', 'g')), 40);
  n_connections integer := least(greatest(coalesce(p_connections, 0), 0), 100);
  v_tool text;
  v_calls integer;
  v_seen integer := 0;
begin
  if p_door is null or p_door not in ('oauth', 'key') then return; end if;
  if v_client = '' then v_client := 'other'; end if;
  if v_surface = '' then v_surface := 'unnamed'; end if;

  if auth.uid() is null and not exists (
    select 1 from access_keys ak
      where ak.key_hash = p_key_hash
        and ak.revoked_at is null
        and (ak.expires_at is null or ak.expires_at > now())
  ) then
    return;
  end if;

  if n_connections > 0 then
    if not exists (select 1 from mcp_daily_surfaces where day = v_today and surface = v_surface)
       and (select count(distinct surface) from mcp_daily_surfaces where day = v_today) >= 50 then
      v_surface := 'other';
    end if;
    insert into mcp_daily_surfaces as s (day, client, door, surface, connections)
      values (v_today, v_client, p_door, v_surface, n_connections)
      on conflict (day, client, door, surface) do update set connections = s.connections + excluded.connections;
  end if;

  if jsonb_typeof(p_tools) = 'object' then
    for v_tool, v_calls in
      select left(regexp_replace(key, '[^a-z0-9_]', '', 'g'), 40), least(greatest(coalesce((value #>> '{}')::integer, 0), 0), 100)
        from jsonb_each(p_tools)
    loop
      v_seen := v_seen + 1;
      exit when v_seen > 20;
      continue when v_tool = '' or v_calls = 0;
      if not exists (select 1 from mcp_daily_tools where day = v_today and tool = v_tool)
         and (select count(distinct tool) from mcp_daily_tools where day = v_today) >= 50 then
        v_tool := 'other';
      end if;
      insert into mcp_daily_tools as t (day, client, door, tool, calls)
        values (v_today, v_client, p_door, v_tool, v_calls)
        on conflict (day, client, door, tool) do update set calls = t.calls + excluded.calls;
    end loop;
  end if;
exception when invalid_text_representation or numeric_value_out_of_range then
  -- A count that is not a number writes nothing rather than failing the caller.
  return;
end $$;

-- Both revokes, then the grant, as for mcp_count.
revoke all on function public.mcp_count_detail(text, text, text, text, integer, jsonb) from public;
revoke all on function public.mcp_count_detail(text, text, text, text, integer, jsonb) from anon, authenticated;
grant execute on function public.mcp_count_detail(text, text, text, text, integer, jsonb) to anon, authenticated;

-- The job log keeps a row per run of every job and nothing pruned it (20,361 rows on
-- 2026-10-08). Daily, keep the last 7 days. Scheduling under a name replaces an earlier one.
select cron.schedule('cron-log-tidy', '41 3 * * *',
  $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$);
