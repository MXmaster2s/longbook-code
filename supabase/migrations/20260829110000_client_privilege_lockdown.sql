-- TRUNCATE ignores row-level security: a role holding it empties every user's rows, not
-- its own. Clients never create triggers or foreign keys either. Supabase's defaults hand
-- all three to both client roles on every new table; withdrawn everywhere.
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;

-- This is also what column_lockdown meant for key_hash: a per-column revoke cannot carve
-- into a table-level grant, so its REFERENCES revoke never took. The statement above takes.

-- The app deletes a hosted copy (revoking the push) and a filed proposal (dismissing it) —
-- nothing else. A key is revoked, never deleted; a tag definition is overwritten.
revoke delete on table public.access_keys from authenticated;
revoke delete on table public.structures from authenticated;
