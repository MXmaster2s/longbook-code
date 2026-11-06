-- A proposal is a ledger edit on its way to the owner's app, not a record to keep. Once
-- applied, the row stays only so a retried agent is answered already_exists; what it
-- carried goes with the stamp. Failed rows keep theirs until the owner dismisses them.
create or replace function public.mcp_pending_writes_forget()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.applied_at is not null and old.applied_at is null then
    new.payload := '{}'::jsonb;
    new.source_ref := null;
  end if;
  return new;
end
$$;

drop trigger if exists mcp_pending_writes_forget on public.mcp_pending_writes;
create trigger mcp_pending_writes_forget
  before update on public.mcp_pending_writes
  for each row execute function public.mcp_pending_writes_forget();

-- The rows applied before this rule.
update public.mcp_pending_writes
  set payload = '{}'::jsonb, source_ref = null
  where applied_at is not null;
