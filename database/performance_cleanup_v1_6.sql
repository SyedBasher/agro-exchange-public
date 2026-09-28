-- Agro-Exchange v1.6: database performance cleanup before controlled deployment.
-- Covers the pre-v1.6 unindexed foreign keys reported by Supabase plus the four
-- Auth/RLS init-plan warnings. Existing unused-index notices are not acted on in an
-- empty development database because absence of use is not evidence the indexes are unnecessary.

create index if not exists buy_orders_buyer_org_idx on public.buy_orders(buyer_organization_id);
create index if not exists buy_orders_created_by_idx on public.buy_orders(created_by_profile_id);
create index if not exists buy_orders_destination_idx on public.buy_orders(destination_location_id);
create index if not exists buy_orders_grade_idx on public.buy_orders(grade_id);
create index if not exists buyer_memberships_profile_idx on public.buyer_memberships(profile_id);
create index if not exists buyer_organizations_location_idx on public.buyer_organizations(location_id);
create index if not exists farms_location_idx on public.farms(location_id);
create index if not exists farms_owner_idx on public.farms(owner_profile_id);
create index if not exists market_observations_grade_idx on public.market_observations(grade_id);
create index if not exists market_observations_location_idx on public.market_observations(location_id);
create index if not exists matches_buy_order_idx on public.matches(buy_order_id);
create index if not exists qc_records_accepted_grade_idx on public.qc_records(accepted_grade_id);
create index if not exists qc_records_location_idx on public.qc_records(location_id);
create index if not exists qc_records_operator_idx on public.qc_records(operator_profile_id);
create index if not exists sell_offers_farm_idx on public.sell_offers(farm_id);
create index if not exists sell_offers_grade_idx on public.sell_offers(grade_id);
create index if not exists sell_offers_origin_idx on public.sell_offers(origin_location_id);
create index if not exists sell_offers_seller_idx on public.sell_offers(seller_profile_id);
create index if not exists shipments_delivery_location_idx on public.shipments(delivery_location_id);
create index if not exists shipments_pickup_location_idx on public.shipments(pickup_location_id);
create index if not exists trade_confirmations_buy_order_idx on public.trade_confirmations(buy_order_id);
create index if not exists trade_confirmations_buyer_accepted_idx on public.trade_confirmations(buyer_accepted_by);
create index if not exists trade_confirmations_buyer_org_idx on public.trade_confirmations(buyer_organization_id);
create index if not exists trade_confirmations_commodity_idx on public.trade_confirmations(commodity_id);
create index if not exists trade_confirmations_destination_idx on public.trade_confirmations(destination_location_id);
create index if not exists trade_confirmations_grade_idx on public.trade_confirmations(grade_id);
create index if not exists trade_confirmations_origin_idx on public.trade_confirmations(origin_location_id);
create index if not exists trade_confirmations_proposed_by_idx on public.trade_confirmations(proposed_by_profile_id);
create index if not exists trade_confirmations_seller_accepted_idx on public.trade_confirmations(seller_accepted_by);
create index if not exists trade_status_events_changed_by_idx on public.trade_status_events(changed_by_profile_id);
create index if not exists trade_status_events_trade_idx on public.trade_status_events(trade_id);
create index if not exists trades_buyer_org_idx on public.trades(buyer_organization_id);
create index if not exists trades_commodity_idx on public.trades(commodity_id);
create index if not exists trades_destination_idx on public.trades(destination_location_id);
create index if not exists trades_grade_idx on public.trades(grade_id);
create index if not exists trades_origin_idx on public.trades(origin_location_id);
create index if not exists trades_seller_idx on public.trades(seller_profile_id);

-- Avoid re-evaluating auth.uid() for every row in these policies.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles for select to authenticated
using (auth_user_id=(select auth.uid()));

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles for insert to authenticated
with check (auth_user_id=(select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
using (auth_user_id=(select auth.uid()))
with check (auth_user_id=(select auth.uid()));

drop policy if exists trade_confirmations_participant_select on public.trade_confirmations;
create policy trade_confirmations_participant_select
on public.trade_confirmations for select to authenticated
using (
  seller_profile_id=(select id from public.profiles where auth_user_id=(select auth.uid()))
  or exists (
    select 1
    from public.buyer_memberships bm
    join public.profiles p on p.id=bm.profile_id
    where p.auth_user_id=(select auth.uid())
      and bm.buyer_organization_id=trade_confirmations.buyer_organization_id
  )
);
