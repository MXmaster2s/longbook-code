-- Postgres hands a new column to every role the table's column grants already name. The
-- Apple ids are the server's business alone: the app reads status and major_version.
revoke select (apple_original_transaction_id, apple_environment) on table public.entitlements
  from authenticated, anon;
