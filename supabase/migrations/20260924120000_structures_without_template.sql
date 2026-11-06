-- A tag carries no template since contract 30, so the structure store keeps each tag's kind,
-- name and icon only. The templates already held are cleared, and a build that still sends
-- one has it dropped before the row is written.
update public.structures set template = null where template is not null;

create or replace function public.structures_without_template()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.template := null;
  return new;
end;
$$;

revoke all on function public.structures_without_template() from public, anon, authenticated;

drop trigger if exists structures_without_template on public.structures;
create trigger structures_without_template
  before insert or update on public.structures
  for each row execute function public.structures_without_template();
