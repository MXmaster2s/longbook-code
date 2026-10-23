-- Supabase's default privileges grant execute on new public functions to anon and
-- authenticated directly, so revoking from PUBLIC alone left the private counter
-- reachable. These name the roles. Applied 2026-08-19, right behind mcp_rate.
revoke all on function public.mcp_rate_bump(text) from public, anon, authenticated, service_role;
revoke all on function public.mcp_rate_check() from anon, service_role;
revoke all on table public.mcp_rate from anon, authenticated, service_role;
