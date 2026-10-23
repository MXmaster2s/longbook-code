-- Two functions ran with the caller's search path. Neither touches a table, so an empty
-- path changes nothing they do and closes the security advisor's warning.
alter function public.mcp_pending_cap() set search_path = '';
alter function public.access_keys_revocation_is_final() set search_path = '';
