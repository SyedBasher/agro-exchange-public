-- Agro-Exchange analytical views for the application layer

create or replace view open_supply_view as
select
  so.id as sell_offer_id,
  c.code as commodity_code,
  c.name_en,
  c.name_bn,
  cg.code as grade_code,
  l.district as origin_district,
  l.upazila as origin_upazila,
  so.remaining_quantity_kg,
  so.minimum_price_bdt_per_kg,
  so.available_from,
  so.available_until,
  p.verified as seller_verified,
  so.created_at
from sell_offers so
join commodities c on c.id=so.commodity_id
left join commodity_grades cg on cg.id=so.grade_id
join locations l on l.id=so.origin_location_id
join profiles p on p.id=so.seller_profile_id
where so.status in ('open','partially_matched') and so.remaining_quantity_kg>0;

create or replace view open_demand_view as
select
  bo.id as buy_order_id,
  c.code as commodity_code,
  c.name_en,
  c.name_bn,
  cg.code as grade_code,
  bo.remaining_quantity_kg,
  bo.target_price_bdt_per_kg,
  bo.delivery_from,
  bo.delivery_until,
  org.name as buyer_name,
  org.buyer_type,
  org.verified as buyer_verified,
  l.district as destination_district,
  bo.created_at
from buy_orders bo
join commodities c on c.id=bo.commodity_id
left join commodity_grades cg on cg.id=bo.grade_id
join buyer_organizations org on org.id=bo.buyer_organization_id
join locations l on l.id=bo.destination_location_id
where bo.status in ('open','partially_matched') and bo.remaining_quantity_kg>0;

create or replace view matching_candidates_view as
select
  s.sell_offer_id,
  d.buy_order_id,
  s.commodity_code,
  s.name_en,
  s.name_bn,
  s.origin_district,
  d.destination_district,
  least(s.remaining_quantity_kg,d.remaining_quantity_kg) as feasible_quantity_kg,
  s.minimum_price_bdt_per_kg as seller_floor_bdt_per_kg,
  d.target_price_bdt_per_kg as buyer_target_bdt_per_kg,
  d.target_price_bdt_per_kg-s.minimum_price_bdt_per_kg as gross_price_room_bdt_per_kg,
  greatest(s.available_from,d.delivery_from) as earliest_feasible_date,
  least(coalesce(s.available_until,'9999-12-31'::date),coalesce(d.delivery_until,'9999-12-31'::date)) as latest_feasible_date,
  s.seller_verified,
  d.buyer_verified,
  d.buyer_name
from open_supply_view s
join open_demand_view d
  on d.commodity_code=s.commodity_code
 and (s.grade_code is null or d.grade_code is null or s.grade_code=d.grade_code)
where greatest(s.available_from,d.delivery_from)
      <= least(coalesce(s.available_until,'9999-12-31'::date),coalesce(d.delivery_until,'9999-12-31'::date));

create or replace view latest_market_observation_view as
select distinct on (mo.commodity_id,mo.location_id,mo.observation_type)
  mo.id,
  c.code as commodity_code,
  c.name_en,
  c.name_bn,
  l.district,
  l.upazila,
  l.market_name,
  mo.observation_type,
  mo.price_bdt_per_kg,
  mo.quantity_kg,
  mo.source_type,
  mo.source_reference,
  mo.verified,
  mo.provenance,
  mo.observed_at
from market_observations mo
join commodities c on c.id=mo.commodity_id
join locations l on l.id=mo.location_id
order by mo.commodity_id,mo.location_id,mo.observation_type,mo.observed_at desc;
