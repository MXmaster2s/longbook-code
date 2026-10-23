-- How much the hosted MCP server is used: per UTC day and per AI application, as its user
-- agent names it, the tool calls answered and the proposals filed. Nothing here identifies a
-- caller — no account, key, address or other identifier is stored, only the two counts.
create table public.mcp_daily_counts (
  day date not null default (now() at time zone 'utc')::date,
  client text not null,
  calls bigint not null default 0 check (calls >= 0),
  edits bigint not null default 0 check (edits >= 0),
  primary key (day, client)
);

-- No policies on purpose: only mcp_count below writes here, and RLS with no policies keeps
-- every client role out. ALL covers TRUNCATE, TRIGGER and REFERENCES; they are named anyway.
alter table public.mcp_daily_counts enable row level security;
revoke all on table public.mcp_daily_counts from public, anon, authenticated;
revoke truncate, trigger, references on table public.mcp_daily_counts from public, anon, authenticated;

-- Adds one request's counts to today's row for that application. Counts only a real caller:
-- a signed-in user, or a key that is neither revoked nor expired. Anything else writes
-- nothing and answers nothing. At most 100 of each per call; labels are cleaned, and past
-- fifty a day a new one counts as other.
create or replace function public.mcp_count(p_key_hash text, p_client text, p_calls integer, p_edits integer)
returns void
language plpgsql security definer set search_path = public as $$
declare
  n_calls integer := least(greatest(coalesce(p_calls, 0), 0), 100);
  n_edits integer := least(greatest(coalesce(p_edits, 0), 0), 100);
  v_today date := (now() at time zone 'utc')::date;
  v_client text := left(btrim(regexp_replace(coalesce(p_client, ''), '[^A-Za-z0-9._ -]', '', 'g')), 40);
begin
  if n_calls = 0 and n_edits = 0 then return; end if;
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

  insert into mcp_daily_counts as c (day, client, calls, edits)
    values (v_today, v_client, n_calls, n_edits)
    on conflict (day, client) do update set
      calls = c.calls + excluded.calls,
      edits = c.edits + excluded.edits;
end $$;

-- Both revokes, then the grant: Postgres gives PUBLIC execute and Supabase gives the two
-- client roles execute by name. The hosted function calls this with the publishable key on
-- the key door and with the caller's own token on the signed-in door.
revoke all on function public.mcp_count(text, text, integer, integer) from public;
revoke all on function public.mcp_count(text, text, integer, integer) from anon, authenticated;
grant execute on function public.mcp_count(text, text, integer, integer) to anon, authenticated;
