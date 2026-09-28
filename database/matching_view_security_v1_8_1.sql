-- Agro-Exchange v1.8.1 — matching-view security follow-up
-- Supabase advisor flagged the two v1.8 matching views as SECURITY DEFINER views.
-- They are internal implementation details behind checked matching RPCs and do
-- not require direct browser SELECT privileges.

begin;

alter view public.open_supply_view set (security_invoker = true);
alter view public.matching_candidates_view set (security_invoker = true);

revoke all on table public.open_supply_view from public, anon, authenticated;
revoke all on table public.matching_candidates_view from public, anon, authenticated;

commit;
