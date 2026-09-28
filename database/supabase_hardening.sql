-- Agro-Exchange Supabase hardening applied to live project.
-- Makes analytical views honor caller RLS and removes unintended anonymous function execution.

alter view open_supply_view set (security_invoker = true);
alter view open_demand_view set (security_invoker = true);
alter view matching_candidates_view set (security_invoker = true);
alter view latest_market_observation_view set (security_invoker = true);

revoke execute on function current_profile_id() from public, anon, authenticated;
revoke execute on function current_user_role() from public, anon, authenticated;

revoke execute on function post_sell_offer(text,text,text,numeric,numeric,date,text) from public, anon;
grant execute on function post_sell_offer(text,text,text,numeric,numeric,date,text) to authenticated;

revoke execute on function get_sell_offer_matches(uuid) from public, anon;
grant execute on function get_sell_offer_matches(uuid) to authenticated;
