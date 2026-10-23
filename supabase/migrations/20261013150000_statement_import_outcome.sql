-- A file the statement reader refused as not a statement is recorded, so the refusal can
-- be seen, but it does not spend the account's monthly share: only read files count.
alter table public.statement_imports
  add column outcome text not null default 'read' check (outcome in ('read', 'refused'));

-- The share is counted over read files in the month; the refused rows stay out of the index.
drop index if exists public.statement_imports_user_started;
create index statement_imports_user_started on public.statement_imports (user_id, started_at desc) where outcome = 'read';
