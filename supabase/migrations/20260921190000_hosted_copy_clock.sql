-- The ninety days are counted on the server's clock, not a device's: whatever a client
-- sends as pushed_at, the row is stamped with the time the server received it.
create or replace function public.stamp_hosted_copy()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.pushed_at := now();
  return new;
end;
$$;

revoke all on function public.stamp_hosted_copy() from public, anon, authenticated;

drop trigger if exists hosted_memories_stamp on public.hosted_memories;
create trigger hosted_memories_stamp
  before insert or update on public.hosted_memories
  for each row execute function public.stamp_hosted_copy();
