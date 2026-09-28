-- Agro-Exchange v1.8 — read-only forensic verification queries
-- Intended for Claude Code / human auditors with read-only Supabase access.
-- DO NOT add INSERT/UPDATE/DELETE/DDL statements to this file.

-- 1. Critical direct-write privileges must remain closed.
select
  has_table_privilege('authenticated','public.profiles','INSERT') as profiles_insert,
  has_table_privilege('authenticated','public.profiles','UPDATE') as profiles_update,
  has_column_privilege('authenticated','public.profiles','role','UPDATE') as profiles_role_update,
  has_column_privilege('authenticated','public.profiles','verified','UPDATE') as profiles_verified_update,
  has_table_privilege('authenticated','public.sell_offers','INSERT') as sell_offers_insert,
  has_table_privilege('authenticated','public.sell_offers','UPDATE') as sell_offers_update,
  has_table_privilege('authenticated','public.buy_orders','INSERT') as buy_orders_insert,
  has_table_privilege('authenticated','public.buy_orders','UPDATE') as buy_orders_update;

-- Expected: every boolean above is false.

-- 2. RLS helper functions are intentionally executable because policies call them.
select
  has_function_privilege('authenticated','public.current_profile_id()','EXECUTE') as current_profile_exec,
  has_function_privilege('authenticated','public.current_user_role()','EXECUTE') as current_role_exec,
  has_function_privilege('authenticated','public.update_my_profile_preferences(text,text)','EXECUTE') as preference_rpc_exec;

-- Expected: every boolean above is true.

-- 3. Current policies for the legacy tables that received v1.8 hardening.
select tablename,policyname,cmd,roles,qual,with_check
from pg_policies
where schemaname='public'
  and tablename in ('profiles','farms','sell_offers','buy_orders')
order by tablename,policyname;

-- 4. Current table grants to authenticated.
select table_name,privilege_type,is_grantable
from information_schema.role_table_grants
where table_schema='public'
  and grantee='authenticated'
  and table_name in ('profiles','farms','sell_offers','buy_orders')
order by table_name,privilege_type;

-- 5. SECURITY DEFINER inventory. Each exposed function must be reviewed for
-- explicit auth/role/ownership checks; a warning alone is not proof of a bug.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       p.provolatile,
       p.proconfig
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef=true
order by p.proname,arguments;

-- 6. Authoritative open supply / matching definitions.
select pg_get_viewdef('public.open_supply_view'::regclass,true) as open_supply_view;
select pg_get_viewdef('public.open_demand_view'::regclass,true) as open_demand_view;
select pg_get_viewdef('public.matching_candidates_view'::regclass,true) as matching_candidates_view;

-- 7. Authoritative matching RPCs.
select pg_get_functiondef('public.get_sell_offer_matches(uuid)'::regprocedure) as sell_match_rpc;
select pg_get_functiondef('public.get_buy_order_matches(uuid)'::regprocedure) as buy_match_rpc;

-- 8. Commercial-party payment RPCs.
select pg_get_functiondef('public.initiate_trade_payment(uuid,text,text,numeric,text)'::regprocedure) as initiate_payment_rpc;
select pg_get_functiondef('public.confirm_trade_payment(uuid,text)'::regprocedure) as confirm_payment_rpc;

-- 9. QC telemetry ownership and active-shipment DB backstop.
select pg_get_functiondef('public.record_qc_telemetry(uuid,text,numeric,text)'::regprocedure) as qc_telemetry_rpc;
select indexname,indexdef
from pg_indexes
where schemaname='public' and indexname='shipments_one_active_per_trade_idx';

-- 10. Non-sensitive row counts / deployment reality. Do not print personal data.
select
  (select count(*) from public.profiles) as profiles,
  (select count(*) from public.profiles where auth_user_id is not null) as auth_linked_profiles,
  (select count(*) from public.sell_offers) as sell_offers,
  (select count(*) from public.buy_orders) as buy_orders,
  (select count(*) from public.trade_confirmations) as trade_confirmations,
  (select count(*) from public.trades) as trades,
  (select count(*) from public.qc_records) as qc_records,
  (select count(*) from public.shipments) as shipments,
  (select count(*) from public.payments) as payments,
  (select count(*) from public.trade_disputes) as disputes;

-- 11. Current feasible seed candidate pairs. This output is commercial test data,
-- not evidence about the Bangladesh market.
select commodity_code,origin_district,destination_district,
       seller_floor_bdt_per_kg,buyer_target_bdt_per_kg,
       indicative_fulfilment_allowance_bdt_per_kg,net_price_room_bdt_per_kg,
       round(100*seller_quantity_coverage,1) as seller_coverage_pct,
       round(100*buyer_quantity_coverage,1) as buyer_coverage_pct,
       earliest_feasible_date
from public.matching_candidates_view
order by commodity_code,origin_district,destination_district;
