-- Agro-Exchange v1.9 — transaction liveness, confidentiality and pilot-operations hardening
-- Round-2 forensic remediation: R2-01, R2-02, R2-03, F2/F2b, F3/F4.
-- This migration deliberately leaves R2-04/R2-05 commercial-policy choices for the next checkpoint.

-- ---------------------------------------------------------------------------
-- 1. Defense in depth: browser roles should not inherit broad write/TRUNCATE
--    privileges on public tables. Trading mutations are RPC-owned.
-- ---------------------------------------------------------------------------
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public
  from anon, authenticated;

alter default privileges in schema public
  revoke insert, update, delete, truncate, references, trigger
  on tables
  from anon, authenticated;

-- Reservation prices / target prices are not a public order book.
revoke select on table public.sell_offers, public.buy_orders from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- 2. Audit fields for decline / shipment cancellation and explicit QC assignment.
-- ---------------------------------------------------------------------------
alter table public.trade_confirmations
  add column if not exists declined_at timestamptz,
  add column if not exists declined_by_profile_id uuid references public.profiles(id),
  add column if not exists decline_reason text;

alter table public.shipments
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by_profile_id uuid references public.profiles(id),
  add column if not exists cancellation_reason text;

alter table public.trades
  add column if not exists qc_operator_profile_id uuid references public.profiles(id),
  add column if not exists qc_assigned_at timestamptz,
  add column if not exists qc_assigned_by_profile_id uuid references public.profiles(id);

create index if not exists trades_qc_operator_idx
  on public.trades(qc_operator_profile_id,status)
  where qc_operator_profile_id is not null;

create index if not exists trade_confirmations_pending_pair_idx
  on public.trade_confirmations(sell_offer_id,buy_order_id,status);

create unique index if not exists trade_confirmations_one_open_pair_idx
  on public.trade_confirmations(sell_offer_id,buy_order_id)
  where status in ('proposed','seller_accepted','buyer_accepted');

-- ---------------------------------------------------------------------------
-- 3. Stale listings cannot match. Existing expired development seeds are closed.
-- ---------------------------------------------------------------------------
update public.sell_offers
set status='closed', updated_at=now()
where status in ('open','matched','partially_matched')
  and available_until is not null
  and available_until < current_date;

update public.buy_orders
set status='closed', updated_at=now()
where status in ('open','matched','partially_matched')
  and delivery_until is not null
  and delivery_until < current_date;

create or replace view public.open_supply_view
with (security_invoker=true)
as
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
from public.sell_offers so
join public.commodities c on c.id=so.commodity_id
left join public.commodity_grades cg on cg.id=so.grade_id
join public.locations l on l.id=so.origin_location_id
join public.profiles p on p.id=so.seller_profile_id
where so.status in ('open','partially_matched')
  and so.remaining_quantity_kg>0
  and p.role='farmer'
  and p.verified=true
  and (so.available_until is null or so.available_until>=current_date);

create or replace view public.open_demand_view
with (security_invoker=true)
as
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
from public.buy_orders bo
join public.commodities c on c.id=bo.commodity_id
left join public.commodity_grades cg on cg.id=bo.grade_id
join public.buyer_organizations org on org.id=bo.buyer_organization_id
join public.locations l on l.id=bo.destination_location_id
where bo.status in ('open','partially_matched')
  and bo.remaining_quantity_kg>0
  and org.verified=true
  and (bo.delivery_until is null or bo.delivery_until>=current_date);

create or replace view public.matching_candidates_view
with (security_invoker=true)
as
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
  d.buyer_name,
  public.indicative_fulfilment_allowance_bdt_per_kg(s.origin_district,d.destination_district) as indicative_fulfilment_allowance_bdt_per_kg,
  d.target_price_bdt_per_kg-s.minimum_price_bdt_per_kg-
    public.indicative_fulfilment_allowance_bdt_per_kg(s.origin_district,d.destination_district) as net_price_room_bdt_per_kg,
  least(s.remaining_quantity_kg,d.remaining_quantity_kg)/nullif(s.remaining_quantity_kg,0) as seller_quantity_coverage,
  least(s.remaining_quantity_kg,d.remaining_quantity_kg)/nullif(d.remaining_quantity_kg,0) as buyer_quantity_coverage
from public.open_supply_view s
join public.open_demand_view d
  on d.commodity_code=s.commodity_code
 and (d.grade_code is null or (s.grade_code is not null and s.grade_code=d.grade_code))
where greatest(s.available_from,d.delivery_from)
      <=least(coalesce(s.available_until,'9999-12-31'::date),coalesce(d.delivery_until,'9999-12-31'::date))
  and s.minimum_price_bdt_per_kg is not null
  and d.target_price_bdt_per_kg is not null
  and s.minimum_price_bdt_per_kg>0
  and d.target_price_bdt_per_kg>0
  and d.target_price_bdt_per_kg-s.minimum_price_bdt_per_kg
      >=public.indicative_fulfilment_allowance_bdt_per_kg(s.origin_district,d.destination_district);

revoke all on public.open_supply_view, public.open_demand_view, public.matching_candidates_view
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Listing management RPCs. Owners can see their own commercial terms
--    without making the order book public.
-- ---------------------------------------------------------------------------
create or replace function public.get_my_sell_offers()
returns table(
  offer_id uuid,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  grade_code text,
  origin_district text,
  quantity_kg numeric,
  remaining_quantity_kg numeric,
  minimum_price_bdt_per_kg numeric,
  available_from date,
  available_until date,
  offer_status text,
  effective_status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.id into v_profile_id
  from public.profiles p
  where p.auth_user_id=auth.uid()
  limit 1;
  if v_profile_id is null then raise exception 'Profile not found'; end if;

  return query
  select
    so.id,c.code,c.name_en,c.name_bn,g.code,l.district,
    so.quantity_kg,so.remaining_quantity_kg,so.minimum_price_bdt_per_kg,
    so.available_from,so.available_until,so.status::text,
    case
      when so.status in ('open','partially_matched') and so.available_until is not null and so.available_until<current_date then 'expired'
      else so.status::text
    end,
    so.created_at
  from public.sell_offers so
  join public.commodities c on c.id=so.commodity_id
  left join public.commodity_grades g on g.id=so.grade_id
  join public.locations l on l.id=so.origin_location_id
  where so.seller_profile_id=v_profile_id
  order by so.created_at desc;
end;
$$;

create or replace function public.get_my_buy_orders()
returns table(
  order_id uuid,
  buyer_organization_id uuid,
  buyer_name text,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  grade_code text,
  destination_district text,
  quantity_kg numeric,
  remaining_quantity_kg numeric,
  target_price_bdt_per_kg numeric,
  delivery_from date,
  delivery_until date,
  order_status text,
  effective_status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.id into v_profile_id
  from public.profiles p
  where p.auth_user_id=auth.uid()
  limit 1;
  if v_profile_id is null then raise exception 'Profile not found'; end if;

  return query
  select
    bo.id,bo.buyer_organization_id,org.name,c.code,c.name_en,c.name_bn,g.code,l.district,
    bo.quantity_kg,bo.remaining_quantity_kg,bo.target_price_bdt_per_kg,
    bo.delivery_from,bo.delivery_until,bo.status::text,
    case
      when bo.status in ('open','partially_matched') and bo.delivery_until is not null and bo.delivery_until<current_date then 'expired'
      else bo.status::text
    end,
    bo.created_at
  from public.buy_orders bo
  join public.buyer_memberships bm
    on bm.buyer_organization_id=bo.buyer_organization_id
   and bm.profile_id=v_profile_id
  join public.buyer_organizations org on org.id=bo.buyer_organization_id
  join public.commodities c on c.id=bo.commodity_id
  left join public.commodity_grades g on g.id=bo.grade_id
  join public.locations l on l.id=bo.destination_location_id
  order by bo.created_at desc;
end;
$$;

create or replace function public.withdraw_sell_offer(p_offer_id uuid,p_reason text default null)
returns table(offer_id uuid,offer_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile_id uuid;v_offer public.sell_offers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.id into v_profile_id from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_profile_id is null then raise exception 'Profile not found'; end if;
  select * into v_offer from public.sell_offers where id=p_offer_id for update;
  if not found then raise exception 'Sell offer not found'; end if;
  if v_offer.seller_profile_id<>v_profile_id then raise exception 'Only the seller can withdraw this offer'; end if;
  if v_offer.status not in ('open','partially_matched') then raise exception 'This offer cannot be withdrawn in its current state'; end if;

  update public.sell_offers set status='cancelled',updated_at=now() where id=v_offer.id;
  update public.trade_confirmations
    set status='declined',declined_at=now(),declined_by_profile_id=v_profile_id,
        decline_reason=coalesce(nullif(btrim(p_reason),''),'Sell offer withdrawn'),updated_at=now()
  where sell_offer_id=v_offer.id and status in ('proposed','seller_accepted','buyer_accepted');

  return query select v_offer.id,'cancelled'::text;
end;
$$;

create or replace function public.withdraw_buy_order(p_order_id uuid,p_reason text default null)
returns table(order_id uuid,order_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile_id uuid;v_order public.buy_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.id into v_profile_id from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_profile_id is null then raise exception 'Profile not found'; end if;
  select * into v_order from public.buy_orders where id=p_order_id for update;
  if not found then raise exception 'Buy order not found'; end if;
  if not exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile_id and bm.buyer_organization_id=v_order.buyer_organization_id
  ) then raise exception 'Buyer-organization membership required'; end if;
  if v_order.status not in ('open','partially_matched') then raise exception 'This order cannot be withdrawn in its current state'; end if;

  update public.buy_orders set status='cancelled',updated_at=now() where id=v_order.id;
  update public.trade_confirmations
    set status='declined',declined_at=now(),declined_by_profile_id=v_profile_id,
        decline_reason=coalesce(nullif(btrim(p_reason),''),'Buy order withdrawn'),updated_at=now()
  where buy_order_id=v_order.id and status in ('proposed','seller_accepted','buyer_accepted');

  return query select v_order.id,'cancelled'::text;
end;
$$;

create or replace function public.amend_sell_offer(
  p_offer_id uuid,
  p_minimum_price numeric,
  p_available_until date
)
returns table(offer_id uuid,offer_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile_id uuid;v_offer public.sell_offers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.id into v_profile_id from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_profile_id is null then raise exception 'Profile not found'; end if;
  select * into v_offer from public.sell_offers where id=p_offer_id for update;
  if not found then raise exception 'Sell offer not found'; end if;
  if v_offer.seller_profile_id<>v_profile_id then raise exception 'Only the seller can amend this offer'; end if;
  if v_offer.status not in ('open','partially_matched') then raise exception 'This offer cannot be amended in its current state'; end if;
  if p_minimum_price is null or p_minimum_price<=0 then raise exception 'Minimum price must be greater than zero'; end if;
  if p_available_until is null or p_available_until<greatest(current_date,v_offer.available_from) then
    raise exception 'Offer end date must be on or after the availability date and today';
  end if;

  update public.sell_offers
  set minimum_price_bdt_per_kg=p_minimum_price,available_until=p_available_until,updated_at=now()
  where id=v_offer.id;

  update public.trade_confirmations
    set status='declined',declined_at=now(),declined_by_profile_id=v_profile_id,
        decline_reason='Sell offer terms changed',updated_at=now()
  where sell_offer_id=v_offer.id and status in ('proposed','seller_accepted','buyer_accepted');

  return query select v_offer.id,v_offer.status::text;
end;
$$;

create or replace function public.amend_buy_order(
  p_order_id uuid,
  p_target_price numeric,
  p_delivery_until date
)
returns table(order_id uuid,order_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile_id uuid;v_order public.buy_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.id into v_profile_id from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_profile_id is null then raise exception 'Profile not found'; end if;
  select * into v_order from public.buy_orders where id=p_order_id for update;
  if not found then raise exception 'Buy order not found'; end if;
  if not exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile_id and bm.buyer_organization_id=v_order.buyer_organization_id
  ) then raise exception 'Buyer-organization membership required'; end if;
  if v_order.status not in ('open','partially_matched') then raise exception 'This order cannot be amended in its current state'; end if;
  if p_target_price is null or p_target_price<=0 then raise exception 'Target price must be greater than zero'; end if;
  if p_delivery_until is null or p_delivery_until<greatest(current_date,v_order.delivery_from) then
    raise exception 'Order end date must be on or after the delivery start date and today';
  end if;

  update public.buy_orders
  set target_price_bdt_per_kg=p_target_price,delivery_until=p_delivery_until,updated_at=now()
  where id=v_order.id;

  update public.trade_confirmations
    set status='declined',declined_at=now(),declined_by_profile_id=v_profile_id,
        decline_reason='Buy order terms changed',updated_at=now()
  where buy_order_id=v_order.id and status in ('proposed','seller_accepted','buyer_accepted');

  return query select v_order.id,v_order.status::text;
end;
$$;

-- Existing seller form has no explicit end-date field yet. Give new offers a clear
-- seven-day pilot validity instead of silently creating perpetual supply.
create or replace function public.post_sell_offer(
  p_commodity_code text,
  p_grade_code text,
  p_origin_district text,
  p_quantity_kg numeric,
  p_minimum_price numeric,
  p_available_from date,
  p_fulfilment_preference text
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile_id uuid;v_role public.user_role;v_verified boolean;v_commodity_id uuid;
  v_grade_id uuid;v_location_id uuid;v_offer_id uuid;v_fulfilment text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select id,role,verified into v_profile_id,v_role,v_verified
  from public.profiles where auth_user_id=auth.uid() limit 1;
  if v_profile_id is null then raise exception 'No Agro-Exchange profile is linked to this account'; end if;
  if v_role not in ('farmer','admin') then raise exception 'Only farmer accounts can post supply in this workflow'; end if;
  if v_role='farmer' and not coalesce(v_verified,false) then raise exception 'Farmer verification is required before posting supply'; end if;
  if p_quantity_kg is null or p_quantity_kg<=0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_minimum_price is null or p_minimum_price<=0 then raise exception 'Minimum price must be greater than zero'; end if;
  if p_available_from is null then raise exception 'Availability date is required'; end if;
  if p_available_from<current_date then raise exception 'Availability date cannot be in the past'; end if;
  v_fulfilment:=coalesce(nullif(btrim(coalesce(p_fulfilment_preference,'')),''),'collection_base');
  if v_fulfilment not in ('collection_base','farm_pickup') then raise exception 'Fulfilment preference is not valid'; end if;
  select id into v_commodity_id from public.commodities where upper(code)=upper(p_commodity_code) and active=true limit 1;
  if v_commodity_id is null then raise exception 'Commodity not found: %',p_commodity_code; end if;
  select id into v_location_id from public.locations where lower(district)=lower(p_origin_district)
    order by (market_name is not null) desc,created_at asc limit 1;
  if v_location_id is null then raise exception 'Origin district not found: %',p_origin_district; end if;
  if p_grade_code is not null and btrim(p_grade_code)<>'' then
    select id into v_grade_id from public.commodity_grades
    where commodity_id=v_commodity_id and upper(code)=upper(p_grade_code) limit 1;
    if v_grade_id is null then raise exception 'Grade is not valid for this commodity'; end if;
  end if;
  insert into public.sell_offers(
    seller_profile_id,commodity_id,grade_id,origin_location_id,quantity_kg,remaining_quantity_kg,
    minimum_price_bdt_per_kg,available_from,available_until,fulfilment_preference,status
  ) values(
    v_profile_id,v_commodity_id,v_grade_id,v_location_id,p_quantity_kg,p_quantity_kg,
    p_minimum_price,p_available_from,p_available_from+7,v_fulfilment,'open'
  ) returning id into v_offer_id;
  return v_offer_id;
end;
$$;

-- Buyer orders also get a seven-day default if no end date is provided.
create or replace function public.post_buy_order(
  p_commodity_code text,
  p_grade_code text,
  p_destination_district text,
  p_quantity_kg numeric,
  p_target_price numeric,
  p_delivery_from date,
  p_delivery_until date
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile_id uuid;v_role public.user_role;v_profile_verified boolean;v_buyer_org_id uuid;
  v_commodity_id uuid;v_grade_id uuid;v_location_id uuid;v_order_id uuid;v_until date;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select id,role,verified into v_profile_id,v_role,v_profile_verified
  from public.profiles where auth_user_id=auth.uid() limit 1;
  if v_profile_id is null then raise exception 'No Agro-Exchange profile is linked to this account'; end if;
  if v_role<>'buyer' or not coalesce(v_profile_verified,false) then raise exception 'Only verified buyer accounts can post demand'; end if;
  select bm.buyer_organization_id into v_buyer_org_id
  from public.buyer_memberships bm
  join public.buyer_organizations org on org.id=bm.buyer_organization_id and org.verified=true
  where bm.profile_id=v_profile_id
  order by bm.buyer_organization_id limit 1;
  if v_buyer_org_id is null then raise exception 'Buyer account is not linked to a verified organization'; end if;
  if p_quantity_kg is null or p_quantity_kg<=0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_target_price is null or p_target_price<=0 then raise exception 'Target price must be greater than zero'; end if;
  if p_delivery_from is null then raise exception 'Delivery start date is required'; end if;
  if p_delivery_from<current_date then raise exception 'Delivery start date cannot be in the past'; end if;
  v_until:=coalesce(p_delivery_until,p_delivery_from+7);
  if v_until<p_delivery_from then raise exception 'Delivery end date cannot be before delivery start date'; end if;
  select id into v_commodity_id from public.commodities where upper(code)=upper(p_commodity_code) and active=true limit 1;
  if v_commodity_id is null then raise exception 'Commodity not found: %',p_commodity_code; end if;
  select id into v_location_id from public.locations where lower(district)=lower(p_destination_district)
    order by (market_name is not null) desc,created_at asc limit 1;
  if v_location_id is null then raise exception 'Destination district not found: %',p_destination_district; end if;
  if p_grade_code is not null and btrim(p_grade_code)<>'' then
    select id into v_grade_id from public.commodity_grades
    where commodity_id=v_commodity_id and upper(code)=upper(p_grade_code) limit 1;
    if v_grade_id is null then raise exception 'Grade is not valid for this commodity'; end if;
  end if;
  insert into public.buy_orders(
    buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,quantity_kg,
    remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
  ) values(
    v_buyer_org_id,v_profile_id,v_commodity_id,v_grade_id,v_location_id,p_quantity_kg,p_quantity_kg,
    p_target_price,p_delivery_from,v_until,'open'
  ) returning id into v_order_id;
  return v_order_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Trade confirmation decline/expiry and date-window enforcement.
-- ---------------------------------------------------------------------------
create or replace function public.decline_trade_confirmation(p_confirmation_id uuid,p_reason text default null)
returns table(confirmation_id uuid,confirmation_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;v_c public.trade_confirmations%rowtype;v_allowed boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  select * into v_c from public.trade_confirmations where id=p_confirmation_id for update;
  if not found then raise exception 'Trade confirmation not found'; end if;
  if v_c.status not in ('proposed','seller_accepted','buyer_accepted') then
    raise exception 'Trade confirmation is no longer open';
  end if;
  v_allowed:=v_c.seller_profile_id=v_profile.id
    or exists(
      select 1 from public.buyer_memberships bm
      where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_c.buyer_organization_id
    );
  if not v_allowed then raise exception 'Trade participant access required'; end if;

  update public.trade_confirmations
  set status='declined',declined_at=now(),declined_by_profile_id=v_profile.id,
      decline_reason=nullif(btrim(coalesce(p_reason,'')),''),updated_at=now()
  where id=v_c.id;

  return query select v_c.id,'declined'::text;
end;
$$;

create or replace function public.propose_trade_confirmation(
  p_sell_offer_id uuid,
  p_buy_order_id uuid,
  p_quantity_kg numeric,
  p_price_bdt_per_kg numeric,
  p_delivery_due_at timestamptz,
  p_payment_terms text default 'Payment after delivery confirmation',
  p_qc_required boolean default true
)
returns table(
  confirmation_id uuid,
  confirmation_reference text,
  confirmation_status text,
  seller_accepted boolean,
  buyer_accepted boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;v_sell public.sell_offers%rowtype;v_buy public.buy_orders%rowtype;
  v_is_seller boolean:=false;v_is_buyer boolean:=false;v_confirmation public.trade_confirmations%rowtype;
  v_ref text;v_window_start date;v_window_end date;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_quantity_kg is null or p_quantity_kg<=0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_price_bdt_per_kg is null or p_price_bdt_per_kg<=0 then raise exception 'Price must be greater than zero'; end if;
  if p_delivery_due_at is null or p_delivery_due_at<now() then raise exception 'Delivery due time must be in the future'; end if;

  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_sell from public.sell_offers where id=p_sell_offer_id for update;
  if not found or v_sell.status not in ('open','matched','partially_matched') then raise exception 'Sell offer is not available'; end if;
  select * into v_buy from public.buy_orders where id=p_buy_order_id for update;
  if not found or v_buy.status not in ('open','matched','partially_matched') then raise exception 'Buy order is not available'; end if;

  if v_sell.available_until is not null and v_sell.available_until<current_date then raise exception 'Sell offer has expired'; end if;
  if v_buy.delivery_until is not null and v_buy.delivery_until<current_date then raise exception 'Buy order has expired'; end if;

  if not exists(select 1 from public.profiles p where p.id=v_sell.seller_profile_id and p.role='farmer' and p.verified=true) then
    raise exception 'Seller is not currently verified for new trades';
  end if;
  if not exists(select 1 from public.buyer_organizations org where org.id=v_buy.buyer_organization_id and org.verified=true) then
    raise exception 'Buyer organization is not currently verified for new trades';
  end if;
  if v_sell.commodity_id<>v_buy.commodity_id then raise exception 'Commodity mismatch'; end if;
  if v_buy.grade_id is not null and (v_sell.grade_id is null or v_sell.grade_id<>v_buy.grade_id) then
    raise exception 'Buyer grade requirement is not confirmed by this sell offer';
  end if;
  if p_quantity_kg>least(v_sell.remaining_quantity_kg,v_buy.remaining_quantity_kg) then
    raise exception 'Quantity exceeds remaining available amount';
  end if;

  v_window_start:=greatest(v_sell.available_from,v_buy.delivery_from);
  v_window_end:=least(coalesce(v_sell.available_until,'9999-12-31'::date),coalesce(v_buy.delivery_until,'9999-12-31'::date));
  if v_window_start>v_window_end then raise exception 'Supply and demand dates no longer overlap'; end if;
  if p_delivery_due_at::date<v_window_start or p_delivery_due_at::date>v_window_end then
    raise exception 'Delivery due date must fall inside the agreed supply/demand window';
  end if;

  v_is_seller:=v_sell.seller_profile_id=v_profile.id;
  v_is_buyer:=v_profile.role='buyer' and v_profile.verified and exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_buy.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then raise exception 'You are not a participant in this potential trade'; end if;

  if exists(
    select 1 from public.trade_confirmations tc
    where tc.sell_offer_id=v_sell.id and tc.buy_order_id=v_buy.id
      and tc.status in ('proposed','seller_accepted','buyer_accepted')
  ) then raise exception 'An open confirmation already exists for this seller-buyer pair'; end if;

  v_ref:='AX-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.trade_confirmations(
    reference,sell_offer_id,buy_order_id,seller_profile_id,buyer_organization_id,commodity_id,grade_id,
    origin_location_id,destination_location_id,agreed_quantity_kg,agreed_price_bdt_per_kg,delivery_due_at,
    payment_terms,qc_required,proposed_by_profile_id,seller_accepted_at,seller_accepted_by,
    buyer_accepted_at,buyer_accepted_by,status,expires_at
  ) values(
    v_ref,v_sell.id,v_buy.id,v_sell.seller_profile_id,v_buy.buyer_organization_id,v_sell.commodity_id,
    coalesce(v_sell.grade_id,v_buy.grade_id),v_sell.origin_location_id,v_buy.destination_location_id,
    p_quantity_kg,p_price_bdt_per_kg,p_delivery_due_at,nullif(trim(p_payment_terms),''),
    coalesce(p_qc_required,true),v_profile.id,
    case when v_is_seller then now() end,case when v_is_seller then v_profile.id end,
    case when v_is_buyer then now() end,case when v_is_buyer then v_profile.id end,
    case when v_is_seller then 'seller_accepted' else 'buyer_accepted' end,now()+interval '48 hours'
  ) returning * into v_confirmation;

  return query select v_confirmation.id,v_confirmation.reference,v_confirmation.status,
    v_confirmation.seller_accepted_at is not null,v_confirmation.buyer_accepted_at is not null;
end;
$$;

create or replace function public.accept_trade_confirmation(p_confirmation_id uuid)
returns table(
  confirmation_id uuid,
  confirmation_reference text,
  confirmation_status text,
  trade_id uuid,
  trade_status text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;v_c public.trade_confirmations%rowtype;
  v_sell public.sell_offers%rowtype;v_buy public.buy_orders%rowtype;
  v_is_seller boolean:=false;v_is_buyer boolean:=false;v_match_id uuid;v_trade_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_c from public.trade_confirmations where id=p_confirmation_id for update;
  if not found then raise exception 'Trade confirmation not found'; end if;
  if v_c.status in ('confirmed','declined','expired') then raise exception 'Trade confirmation is no longer open'; end if;

  if v_c.expires_at is not null and v_c.expires_at<now() then
    update public.trade_confirmations set status='expired',updated_at=now() where id=v_c.id;
    return query select v_c.id,v_c.reference,'expired'::text,v_c.trade_id,null::text;
    return;
  end if;

  select * into v_sell from public.sell_offers where id=v_c.sell_offer_id for update;
  select * into v_buy from public.buy_orders where id=v_c.buy_order_id for update;
  if not found then raise exception 'Underlying marketplace listing not found'; end if;
  if v_sell.status not in ('open','matched','partially_matched')
     or (v_sell.available_until is not null and v_sell.available_until<current_date)
     or v_buy.status not in ('open','matched','partially_matched')
     or (v_buy.delivery_until is not null and v_buy.delivery_until<current_date) then
    update public.trade_confirmations
      set status='expired',updated_at=now(),decline_reason='Underlying listing expired or withdrawn'
      where id=v_c.id;
    return query select v_c.id,v_c.reference,'expired'::text,v_c.trade_id,null::text;
    return;
  end if;

  if not exists(select 1 from public.profiles p where p.id=v_c.seller_profile_id and p.role='farmer' and p.verified=true) then
    raise exception 'Seller is not currently verified for new trades';
  end if;
  if not exists(select 1 from public.buyer_organizations org where org.id=v_c.buyer_organization_id and org.verified=true) then
    raise exception 'Buyer organization is not currently verified for new trades';
  end if;

  v_is_seller:=v_c.seller_profile_id=v_profile.id;
  v_is_buyer:=v_profile.role='buyer' and v_profile.verified and exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_c.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then raise exception 'You are not a participant in this trade confirmation'; end if;

  if v_is_seller and v_c.seller_accepted_at is null then
    update public.trade_confirmations set seller_accepted_at=now(),seller_accepted_by=v_profile.id,updated_at=now() where id=v_c.id;
  end if;
  if v_is_buyer and v_c.buyer_accepted_at is null then
    update public.trade_confirmations set buyer_accepted_at=now(),buyer_accepted_by=v_profile.id,updated_at=now() where id=v_c.id;
  end if;

  select * into v_c from public.trade_confirmations where id=p_confirmation_id for update;
  if v_c.seller_accepted_at is not null and v_c.buyer_accepted_at is not null then
    if v_sell.remaining_quantity_kg<v_c.agreed_quantity_kg or v_buy.remaining_quantity_kg<v_c.agreed_quantity_kg then
      raise exception 'Available quantity changed before confirmation';
    end if;
    insert into public.matches(
      sell_offer_id,buy_order_id,matched_quantity_kg,proposed_price_bdt_per_kg,status,score,scoring_version,scoring_factors
    ) values(
      v_c.sell_offer_id,v_c.buy_order_id,v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,
      'converted',null,'trade-confirmation-v1.9',jsonb_build_object('confirmation_reference',v_c.reference)
    ) returning id into v_match_id;
    insert into public.trades(
      match_id,seller_profile_id,buyer_organization_id,commodity_id,grade_id,origin_location_id,
      destination_location_id,agreed_quantity_kg,agreed_price_bdt_per_kg,delivery_due_at,payment_terms,status
    ) values(
      v_match_id,v_c.seller_profile_id,v_c.buyer_organization_id,v_c.commodity_id,v_c.grade_id,
      v_c.origin_location_id,v_c.destination_location_id,v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,
      v_c.delivery_due_at,v_c.payment_terms,'confirmed'
    ) returning id into v_trade_id;
    update public.trade_confirmations set status='confirmed',trade_id=v_trade_id,updated_at=now() where id=v_c.id;
    update public.sell_offers
      set remaining_quantity_kg=remaining_quantity_kg-v_c.agreed_quantity_kg,
          status=case when remaining_quantity_kg-v_c.agreed_quantity_kg<=0 then 'closed'::public.order_status else 'partially_matched'::public.order_status end,
          updated_at=now()
      where id=v_c.sell_offer_id;
    update public.buy_orders
      set remaining_quantity_kg=remaining_quantity_kg-v_c.agreed_quantity_kg,
          status=case when remaining_quantity_kg-v_c.agreed_quantity_kg<=0 then 'closed'::public.order_status else 'partially_matched'::public.order_status end,
          updated_at=now()
      where id=v_c.buy_order_id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade_id,'confirmed',v_profile.id,jsonb_build_object(
        'confirmation_reference',v_c.reference,'qc_required',v_c.qc_required,'event_type','trade_confirmed'
      ));
  else
    update public.trade_confirmations
      set status=case when seller_accepted_at is not null then 'seller_accepted' else 'buyer_accepted' end,
          updated_at=now()
      where id=v_c.id;
  end if;

  select * into v_c from public.trade_confirmations where id=p_confirmation_id;
  return query select v_c.id,v_c.reference,v_c.status,v_c.trade_id,
    case when v_c.trade_id is not null then (select t.status::text from public.trades t where t.id=v_c.trade_id) else null end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. QC assignment + QC-rejection resume state.
-- ---------------------------------------------------------------------------
create or replace function public.assign_trade_qc(p_trade_id uuid,p_qc_operator_profile_id uuid)
returns table(trade_id uuid,qc_operator_profile_id uuid,trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_actor public.profiles%rowtype;v_operator public.profiles%rowtype;v_trade public.trades%rowtype;v_required boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_actor from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_actor.role not in ('field_agent','admin') then raise exception 'Field-agent or admin access required'; end if;
  select * into v_operator from public.profiles where id=p_qc_operator_profile_id;
  if not found or v_operator.role<>'qc_operator' or not v_operator.verified then
    raise exception 'A verified QC operator must be selected';
  end if;
  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  select coalesce(tc.qc_required,true) into v_required from public.trade_confirmations tc where tc.trade_id=v_trade.id limit 1;
  if not coalesce(v_required,true) then raise exception 'QC is not required for this trade'; end if;
  if v_trade.status not in ('confirmed','awaiting_qc') then raise exception 'Trade is not available for QC assignment'; end if;

  update public.trades
  set qc_operator_profile_id=v_operator.id,qc_assigned_at=now(),qc_assigned_by_profile_id=v_actor.id,updated_at=now()
  where id=v_trade.id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,v_trade.status,v_actor.id,jsonb_build_object(
    'event_type','qc_operator_assigned','qc_operator_profile_id',v_operator.id
  ));

  return query select v_trade.id,v_operator.id,v_trade.status::text;
end;
$$;

create or replace function public.begin_trade_qc(p_trade_id uuid)
returns table(trade_id uuid,trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;v_trade public.trades%rowtype;v_required boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator access required'; end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_profile.role='qc_operator' and v_trade.qc_operator_profile_id is distinct from v_profile.id then
    raise exception 'This trade is assigned to another QC operator';
  end if;

  select coalesce(tc.qc_required,true) into v_required
  from public.trade_confirmations tc where tc.trade_id=v_trade.id limit 1;
  if not coalesce(v_required,true) then raise exception 'QC is not required for this trade'; end if;

  if v_trade.status='confirmed' then
    update public.trades set status='awaiting_qc',updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'awaiting_qc',v_profile.id,jsonb_build_object('workflow','qc-v1.9','event_type','qc_started'));
  elsif v_trade.status<>'awaiting_qc' then
    raise exception 'Trade is not available for QC in its current state: %',v_trade.status;
  end if;

  return query select v_trade.id,(select t.status::text from public.trades t where t.id=v_trade.id);
end;
$$;

create or replace function public.record_trade_qc(
  p_trade_id uuid,
  p_measured_weight_kg numeric,
  p_accepted_grade_code text,
  p_accepted boolean,
  p_certified_scale boolean default false,
  p_scale_reference text default null,
  p_weighing_method text default 'digital_scale',
  p_notes text default null,
  p_evidence_objects jsonb default '[]'::jsonb
)
returns table(qc_record_id uuid,trade_id uuid,trade_status text,weight_variance_pct numeric,evidence_count integer)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;v_trade public.trades%rowtype;v_grade_id uuid;v_record_id uuid;
  v_new_status public.trade_status;v_variance numeric;v_evidence jsonb:=coalesce(p_evidence_objects,'[]'::jsonb);
  v_path text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator access required'; end if;
  if p_measured_weight_kg is null or p_measured_weight_kg<=0 then raise exception 'Measured weight must be greater than zero'; end if;
  if p_accepted is null then raise exception 'QC acceptance decision is required'; end if;
  if jsonb_typeof(v_evidence)<>'array' then raise exception 'Evidence must be a JSON array'; end if;
  if jsonb_array_length(v_evidence)>4 then raise exception 'A maximum of four QC evidence images is allowed'; end if;
  if coalesce(p_certified_scale,false) and nullif(btrim(coalesce(p_scale_reference,'')),'') is null then
    raise exception 'Scale reference is required when certified scale is selected';
  end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_profile.role='qc_operator' and v_trade.qc_operator_profile_id is distinct from v_profile.id then
    raise exception 'This trade is assigned to another QC operator';
  end if;
  if v_trade.status not in ('confirmed','awaiting_qc') then
    raise exception 'Trade is not available for QC in its current state: %',v_trade.status;
  end if;

  -- Evidence objects, when provided, must be scoped to this trade path.
  for v_path in select jsonb_array_elements_text(v_evidence)
  loop
    if split_part(v_path,'/',1)<>v_trade.id::text then
      raise exception 'QC evidence must be stored under the trade id path';
    end if;
  end loop;

  if v_trade.status='confirmed' then
    update public.trades set status='awaiting_qc',updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'awaiting_qc',v_profile.id,jsonb_build_object('workflow','qc-v1.9','auto_started',true,'event_type','qc_started'));
  end if;

  v_grade_id:=v_trade.grade_id;
  if nullif(btrim(coalesce(p_accepted_grade_code,'')),'') is not null then
    select cg.id into v_grade_id
    from public.commodity_grades cg
    where cg.commodity_id=v_trade.commodity_id and upper(cg.code)=upper(p_accepted_grade_code)
    limit 1;
    if v_grade_id is null then raise exception 'Accepted grade not found for this commodity'; end if;
  end if;

  insert into public.qc_records(
    trade_id,operator_profile_id,location_id,measured_weight_kg,accepted_grade_id,accepted,
    notes,photo_urls,certified_scale,scale_reference,weighing_method,evidence_objects
  ) values(
    v_trade.id,v_profile.id,v_trade.origin_location_id,p_measured_weight_kg,v_grade_id,p_accepted,
    nullif(btrim(coalesce(p_notes,'')),''),v_evidence,coalesce(p_certified_scale,false),
    nullif(btrim(coalesce(p_scale_reference,'')),''),coalesce(nullif(btrim(p_weighing_method),''),'digital_scale'),v_evidence
  ) returning id into v_record_id;

  v_variance:=round(100*(p_measured_weight_kg-v_trade.agreed_quantity_kg)/nullif(v_trade.agreed_quantity_kg,0),2);
  v_new_status:=case when p_accepted then 'ready_for_dispatch'::public.trade_status else 'disputed'::public.trade_status end;

  update public.trades set status=v_new_status,updated_at=now() where id=v_trade.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(
    v_trade.id,v_new_status,v_profile.id,
    jsonb_build_object(
      'workflow','qc-v1.9',
      'event_type',case when p_accepted then 'qc_accepted' else 'qc_rejected' end,
      'qc_record_id',v_record_id,'accepted',p_accepted,'measured_weight_kg',p_measured_weight_kg,
      'weight_variance_pct',v_variance,'certified_scale',coalesce(p_certified_scale,false),
      'scale_reference',nullif(btrim(coalesce(p_scale_reference,'')),''),'evidence_count',jsonb_array_length(v_evidence)
    )
  );

  return query select v_record_id,v_trade.id,v_new_status::text,v_variance,jsonb_array_length(v_evidence);
end;
$$;

create or replace function public.open_trade_dispute(
  p_trade_id uuid,
  p_dispute_type text,
  p_summary text,
  p_details text default null,
  p_evidence_objects jsonb default '[]'::jsonb
)
returns table(dispute_id uuid,dispute_status text,trade_status text,resume_trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;v_trade public.trades%rowtype;v_allowed boolean:=false;
  v_resume public.trade_status;v_event_type text;v_dispute_id uuid;v_evidence jsonb:=coalesce(p_evidence_objects,'[]'::jsonb);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_allowed:=v_trade.seller_profile_id=v_profile.id
    or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id)
    or v_profile.role='admin';
  if not v_allowed then raise exception 'Trade participant or admin access required'; end if;
  if v_trade.status in ('settled','cancelled') then raise exception 'A settled or cancelled trade cannot open a new dispute'; end if;
  if p_dispute_type not in ('quantity_shortfall','grade_mismatch','damage_condition','delivery_rejection','payment_issue','other') then
    raise exception 'Unsupported dispute type';
  end if;
  if char_length(btrim(coalesce(p_summary,'')))<3 then raise exception 'Dispute summary is required'; end if;
  if jsonb_typeof(v_evidence)<>'array' or jsonb_array_length(v_evidence)>4 then
    raise exception 'Evidence must be an array with at most four objects';
  end if;
  if exists(select 1 from public.trade_disputes d where d.trade_id=p_trade_id and d.status in ('open','proposal_pending')) then
    raise exception 'An active dispute already exists for this trade';
  end if;

  if v_trade.status='disputed' then
    select e.metadata->>'event_type' into v_event_type
    from public.trade_status_events e
    where e.trade_id=v_trade.id and e.status='disputed'
    order by e.created_at desc,e.id desc limit 1;

    if v_event_type='buyer_receipt_disputed' then
      v_resume:='delivered'::public.trade_status;
    elsif v_event_type in ('qc_rejected','qc_failed') then
      v_resume:='ready_for_dispatch'::public.trade_status;
    else
      raise exception 'Cannot determine a safe resume state for this disputed trade';
    end if;
  else
    v_resume:=v_trade.status;
  end if;

  insert into public.trade_disputes(
    trade_id,opened_by_profile_id,dispute_type,summary,details,evidence_objects,status,resume_trade_status
  ) values(
    v_trade.id,v_profile.id,p_dispute_type,btrim(p_summary),nullif(btrim(coalesce(p_details,'')),''),v_evidence,'open',v_resume
  ) returning id into v_dispute_id;

  if v_trade.status<>'disputed' then
    update public.trades set status='disputed',updated_at=now() where id=v_trade.id;
  end if;
  update public.payment_obligations
  set status=case when status='paid' then status else 'disputed' end,updated_at=now()
  where trade_id=v_trade.id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,'disputed',v_profile.id,jsonb_build_object(
    'event_type','trade_dispute_opened','dispute_id',v_dispute_id,'dispute_type',p_dispute_type,'resume_status',v_resume::text
  ));

  return query select v_dispute_id,'open'::text,'disputed'::text,v_resume::text;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Shipment cancellation / reassignment path.
-- ---------------------------------------------------------------------------
create or replace function public.cancel_shipment(p_shipment_id uuid,p_reason text)
returns table(shipment_id uuid,shipment_status text,trade_id uuid,trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_actor public.profiles%rowtype;v_shipment public.shipments%rowtype;v_trade public.trades%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_actor from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_actor.role not in ('field_agent','admin') then raise exception 'Field-agent or admin access required'; end if;
  if char_length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Cancellation reason is required'; end if;

  select * into v_shipment from public.shipments where id=p_shipment_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  select * into v_trade from public.trades where id=v_shipment.trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_shipment.status not in ('assigned','accepted','in_transit') then raise exception 'Shipment cannot be cancelled in its current state'; end if;
  if v_shipment.status='in_transit' and v_actor.role<>'admin' then
    raise exception 'Only admin can cancel a shipment already in transit';
  end if;

  update public.shipments
  set status='cancelled',cancelled_at=now(),cancelled_by_profile_id=v_actor.id,
      cancellation_reason=btrim(p_reason)
  where id=v_shipment.id;

  if v_trade.status='in_transit' then
    update public.trades set status='ready_for_dispatch',updated_at=now() where id=v_trade.id;
    v_trade.status:='ready_for_dispatch';
  end if;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,v_trade.status,v_actor.id,jsonb_build_object(
    'event_type','shipment_cancelled','shipment_id',v_shipment.id,'reason',btrim(p_reason)
  ));

  return query select v_shipment.id,'cancelled'::text,v_trade.id,v_trade.status::text;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Restore marketplace inventory exactly once when a trade is cancelled.
-- ---------------------------------------------------------------------------
create or replace function public.restore_trade_inventory_after_cancel(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_trade public.trades%rowtype;v_match public.matches%rowtype;
begin
  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if exists(
    select 1 from public.trade_status_events e
    where e.trade_id=p_trade_id and e.metadata->>'event_type'='inventory_restored_after_cancellation'
  ) then return; end if;
  if v_trade.match_id is null then return; end if;
  select * into v_match from public.matches where id=v_trade.match_id;
  if not found then return; end if;

  update public.sell_offers so
  set remaining_quantity_kg=least(so.quantity_kg,so.remaining_quantity_kg+v_trade.agreed_quantity_kg),
      status=case
        when so.status='cancelled' then 'cancelled'::public.order_status
        when so.available_until is not null and so.available_until<current_date then 'closed'::public.order_status
        when least(so.quantity_kg,so.remaining_quantity_kg+v_trade.agreed_quantity_kg)>=so.quantity_kg then 'open'::public.order_status
        else 'partially_matched'::public.order_status
      end,
      updated_at=now()
  where so.id=v_match.sell_offer_id;

  update public.buy_orders bo
  set remaining_quantity_kg=least(bo.quantity_kg,bo.remaining_quantity_kg+v_trade.agreed_quantity_kg),
      status=case
        when bo.status='cancelled' then 'cancelled'::public.order_status
        when bo.delivery_until is not null and bo.delivery_until<current_date then 'closed'::public.order_status
        when least(bo.quantity_kg,bo.remaining_quantity_kg+v_trade.agreed_quantity_kg)>=bo.quantity_kg then 'open'::public.order_status
        else 'partially_matched'::public.order_status
      end,
      updated_at=now()
  where bo.id=v_match.buy_order_id;

  insert into public.trade_status_events(trade_id,status,metadata)
  values(v_trade.id,'cancelled',jsonb_build_object(
    'event_type','inventory_restored_after_cancellation',
    'sell_offer_id',v_match.sell_offer_id,
    'buy_order_id',v_match.buy_order_id,
    'restored_quantity_kg',v_trade.agreed_quantity_kg
  ));
end;
$$;

revoke all on function public.restore_trade_inventory_after_cancel(uuid) from public,anon,authenticated;

-- Replace the dispute-response function only to add inventory restoration to
-- full rejection / cancellation. All existing two-party consent and payment
-- guards are preserved.
create or replace function public.respond_trade_adjustment(p_proposal_id uuid,p_accept boolean,p_note text default null)
returns table(
  proposal_id uuid,proposal_status text,dispute_status text,trade_status text,
  amount_due_bdt numeric,seller_accepted boolean,buyer_accepted boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;v_proposal public.trade_adjustment_proposals%rowtype;
  v_dispute public.trade_disputes%rowtype;v_trade public.trades%rowtype;
  v_is_seller boolean:=false;v_is_buyer boolean:=false;v_confirmed numeric(16,2):=0;v_initiated integer:=0;
  v_final_amount numeric(16,2);v_final_qty numeric(14,2);v_final_price numeric(12,2);v_final_grade uuid;
  v_obligation public.payment_obligations%rowtype;v_has_obligation boolean:=false;v_next_status public.trade_status;
  v_obligation_status text;v_seller_ok boolean;v_buyer_ok boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  select * into v_proposal from public.trade_adjustment_proposals where id=p_proposal_id for update;
  if not found then raise exception 'Proposal not found'; end if;
  if v_proposal.status<>'pending' then raise exception 'Proposal is no longer pending'; end if;
  select * into v_dispute from public.trade_disputes where id=v_proposal.dispute_id for update;
  select * into v_trade from public.trades where id=v_dispute.trade_id for update;

  v_is_seller:=v_trade.seller_profile_id=v_profile.id;
  v_is_buyer:=exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then
    if v_profile.role='admin' then raise exception 'Commercial party acceptance is required; admin cannot substitute for seller or buyer'; end if;
    raise exception 'Trade participant access required';
  end if;

  if not coalesce(p_accept,false) then
    update public.trade_adjustment_proposals
      set status='rejected',rejected_by_profile_id=v_profile.id,
          rejection_note=nullif(btrim(coalesce(p_note,'')),''),updated_at=now()
    where id=v_proposal.id;
    update public.trade_disputes set status='open',updated_at=now() where id=v_dispute.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'disputed',v_profile.id,jsonb_build_object(
        'event_type','adjustment_rejected','dispute_id',v_dispute.id,'proposal_id',v_proposal.id
      ));
    return query select v_proposal.id,'rejected'::text,'open'::text,'disputed'::text,
      v_proposal.proposed_amount_due_bdt,(v_proposal.seller_accepted_at is not null),(v_proposal.buyer_accepted_at is not null);
    return;
  end if;

  if v_is_seller and v_proposal.seller_accepted_at is null then
    update public.trade_adjustment_proposals
      set seller_accepted_by=v_profile.id,seller_accepted_at=now(),updated_at=now()
    where id=v_proposal.id;
  end if;
  if v_is_buyer and v_proposal.buyer_accepted_at is null then
    update public.trade_adjustment_proposals
      set buyer_accepted_by=v_profile.id,buyer_accepted_at=now(),updated_at=now()
    where id=v_proposal.id;
  end if;

  select * into v_proposal from public.trade_adjustment_proposals where id=p_proposal_id for update;
  v_seller_ok:=v_proposal.seller_accepted_at is not null;
  v_buyer_ok:=v_proposal.buyer_accepted_at is not null;
  if not (v_seller_ok and v_buyer_ok) then
    return query select v_proposal.id,'pending'::text,'proposal_pending'::text,'disputed'::text,
      v_proposal.proposed_amount_due_bdt,v_seller_ok,v_buyer_ok;
    return;
  end if;

  select count(*) into v_initiated from public.payments p where p.trade_id=v_trade.id and p.status='initiated';
  if v_initiated>0 then raise exception 'An initiated payment must be confirmed or marked failed before the adjustment can be finalized'; end if;
  select coalesce(sum(p.amount_bdt),0) into v_confirmed from public.payments p where p.trade_id=v_trade.id and p.status='confirmed';
  v_final_amount:=coalesce(v_proposal.proposed_amount_due_bdt,0);
  if v_confirmed>v_final_amount+0.01 then
    raise exception 'Confirmed payments exceed the proposed amount. Refund/credit handling is required before this adjustment can be finalized';
  end if;

  if v_proposal.resolution_type in ('full_rejection','cancel_trade') then
    if v_confirmed>0.01 then raise exception 'A zero-value cancellation cannot be finalized after confirmed payment without refund handling'; end if;
    v_next_status:='cancelled'::public.trade_status;
    update public.payment_obligations set amount_due_bdt=0,status='cancelled',updated_at=now() where trade_id=v_trade.id;
  else
    v_final_qty:=coalesce(v_proposal.proposed_quantity_kg,v_trade.agreed_quantity_kg);
    v_final_price:=coalesce(v_proposal.proposed_unit_price_bdt_per_kg,v_trade.agreed_price_bdt_per_kg);
    v_final_grade:=coalesce(v_proposal.proposed_grade_id,v_trade.grade_id);
    v_final_amount:=round(v_final_qty*v_final_price,2);

    select * into v_obligation from public.payment_obligations where trade_id=v_trade.id for update;
    v_has_obligation:=found;
    if v_has_obligation then
      v_obligation_status:=case
        when v_final_amount<=v_confirmed+0.01 then 'paid'
        when v_confirmed>0 then 'partially_paid'
        else 'due'
      end;
      update public.payment_obligations
      set basis_quantity_kg=v_final_qty,unit_price_bdt_per_kg=v_final_price,amount_due_bdt=v_final_amount,
          status=v_obligation_status,
          due_at=case when v_obligation_status='paid' then due_at else coalesce(due_at,now()) end,
          updated_at=now()
      where trade_id=v_trade.id;
    end if;

    if v_has_obligation and v_final_amount<=v_confirmed+0.01 then
      v_next_status:='settled'::public.trade_status;
    else
      v_next_status:=v_dispute.resume_trade_status;
      if v_next_status='disputed' then raise exception 'Resolved dispute has no safe resume state'; end if;
    end if;
  end if;

  update public.trade_adjustment_proposals
    set status='accepted',applied_at=now(),updated_at=now(),proposed_amount_due_bdt=v_final_amount
  where id=v_proposal.id;
  update public.trade_disputes
    set status='resolved',resolution_type=v_proposal.resolution_type,resolved_at=now(),updated_at=now()
  where id=v_dispute.id;
  update public.trades
    set status=v_next_status,
        settled_at=case when v_next_status='settled' then coalesce(settled_at,now()) else settled_at end,
        updated_at=now()
  where id=v_trade.id;

  if v_next_status='cancelled' then
    perform public.restore_trade_inventory_after_cancel(v_trade.id);
  end if;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,v_next_status,v_profile.id,jsonb_build_object(
    'event_type','trade_adjustment_applied','dispute_id',v_dispute.id,'proposal_id',v_proposal.id,
    'resolution_type',v_proposal.resolution_type,'effective_quantity_kg',v_final_qty,
    'effective_unit_price_bdt_per_kg',v_final_price,'effective_grade_id',v_final_grade,
    'amount_due_bdt',v_final_amount,'confirmed_payments_bdt',v_confirmed
  ));

  return query select v_proposal.id,'accepted'::text,'resolved'::text,v_next_status::text,v_final_amount,true,true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. QC evidence Storage must be trade-scoped and assignment-scoped.
-- ---------------------------------------------------------------------------
drop policy if exists qc_evidence_insert_operator on storage.objects;
drop policy if exists qc_evidence_select_participant on storage.objects;
drop policy if exists qc_evidence_delete_admin on storage.objects;

create policy qc_evidence_insert_operator
on storage.objects
for insert
to authenticated
with check (
  bucket_id='qc-evidence'
  and exists(
    select 1
    from public.profiles p
    left join public.trades t
      on t.id::text=split_part(storage.objects.name,'/',1)
    where p.auth_user_id=(select auth.uid())
      and (
        p.role='admin'
        or (
          p.role='qc_operator'
          and p.verified=true
          and t.qc_operator_profile_id=p.id
          and t.status in ('confirmed','awaiting_qc')
        )
      )
  )
);

create policy qc_evidence_select_participant
on storage.objects
for select
to authenticated
using (
  bucket_id='qc-evidence'
  and exists(
    select 1
    from public.trades t
    where t.id::text=split_part(storage.objects.name,'/',1)
      and (
        t.seller_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
        or exists(
          select 1 from public.buyer_memberships bm
          join public.profiles p on p.id=bm.profile_id
          where p.auth_user_id=(select auth.uid())
            and bm.buyer_organization_id=t.buyer_organization_id
        )
        or t.qc_operator_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
        or exists(
          select 1 from public.profiles p
          where p.auth_user_id=(select auth.uid()) and p.role='admin'
        )
      )
  )
);

create policy qc_evidence_delete_admin
on storage.objects
for delete
to authenticated
using (
  bucket_id='qc-evidence'
  and exists(
    select 1 from public.profiles p
    where p.auth_user_id=(select auth.uid()) and p.role='admin'
  )
);

-- Optimize the two delivery policies while we are touching the same class of finding.
drop policy if exists delivery_evidence_insert on storage.objects;
drop policy if exists delivery_evidence_select on storage.objects;

create policy delivery_evidence_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id='delivery-evidence'
  and (
    exists(select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
    or exists(
      select 1
      from public.profiles p
      join public.shipments s on s.transporter_profile_id=p.id
      where p.auth_user_id=(select auth.uid())
        and p.role='transporter'
        and s.trade_id::text=split_part(storage.objects.name,'/',1)
        and s.status in ('assigned','accepted','in_transit')
    )
  )
);

create policy delivery_evidence_select
on storage.objects
for select
to authenticated
using (
  bucket_id='delivery-evidence'
  and (
    exists(select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
    or exists(
      select 1 from public.profiles p
      join public.shipments s on s.transporter_profile_id=p.id
      where p.auth_user_id=(select auth.uid()) and s.trade_id::text=split_part(storage.objects.name,'/',1)
    )
    or exists(
      select 1 from public.profiles p
      join public.trades t on t.seller_profile_id=p.id
      where p.auth_user_id=(select auth.uid()) and t.id::text=split_part(storage.objects.name,'/',1)
    )
    or exists(
      select 1 from public.profiles p
      join public.buyer_memberships bm on bm.profile_id=p.id
      join public.trades t on t.buyer_organization_id=bm.buyer_organization_id
      where p.auth_user_id=(select auth.uid()) and t.id::text=split_part(storage.objects.name,'/',1)
    )
  )
);

-- ---------------------------------------------------------------------------
-- 10. Grants: only intended browser RPCs are exposed.
-- ---------------------------------------------------------------------------
revoke all on function public.get_my_sell_offers() from public,anon;
revoke all on function public.get_my_buy_orders() from public,anon;
revoke all on function public.withdraw_sell_offer(uuid,text) from public,anon;
revoke all on function public.withdraw_buy_order(uuid,text) from public,anon;
revoke all on function public.amend_sell_offer(uuid,numeric,date) from public,anon;
revoke all on function public.amend_buy_order(uuid,numeric,date) from public,anon;
revoke all on function public.decline_trade_confirmation(uuid,text) from public,anon;
revoke all on function public.assign_trade_qc(uuid,uuid) from public,anon;
revoke all on function public.cancel_shipment(uuid,text) from public,anon;

grant execute on function public.get_my_sell_offers() to authenticated;
grant execute on function public.get_my_buy_orders() to authenticated;
grant execute on function public.withdraw_sell_offer(uuid,text) to authenticated;
grant execute on function public.withdraw_buy_order(uuid,text) to authenticated;
grant execute on function public.amend_sell_offer(uuid,numeric,date) to authenticated;
grant execute on function public.amend_buy_order(uuid,numeric,date) to authenticated;
grant execute on function public.decline_trade_confirmation(uuid,text) to authenticated;
grant execute on function public.assign_trade_qc(uuid,uuid) to authenticated;
grant execute on function public.cancel_shipment(uuid,text) to authenticated;

-- Existing replaced RPCs keep their authenticated execute grants; make that explicit.
grant execute on function public.post_sell_offer(text,text,text,numeric,numeric,date,text) to authenticated;
grant execute on function public.post_buy_order(text,text,text,numeric,numeric,date,date) to authenticated;
grant execute on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) to authenticated;
grant execute on function public.accept_trade_confirmation(uuid) to authenticated;
grant execute on function public.begin_trade_qc(uuid) to authenticated;
grant execute on function public.record_trade_qc(uuid,numeric,text,boolean,boolean,text,text,text,jsonb) to authenticated;
grant execute on function public.open_trade_dispute(uuid,text,text,text,jsonb) to authenticated;
grant execute on function public.respond_trade_adjustment(uuid,boolean,text) to authenticated;

revoke all on function public.post_sell_offer(text,text,text,numeric,numeric,date,text) from anon,public;
revoke all on function public.post_buy_order(text,text,text,numeric,numeric,date,date) from anon,public;
revoke all on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) from anon,public;
revoke all on function public.accept_trade_confirmation(uuid) from anon,public;
revoke all on function public.begin_trade_qc(uuid) from anon,public;
revoke all on function public.record_trade_qc(uuid,numeric,text,boolean,boolean,text,text,text,jsonb) from anon,public;
revoke all on function public.open_trade_dispute(uuid,text,text,text,jsonb) from anon,public;
revoke all on function public.respond_trade_adjustment(uuid,boolean,text) from anon,public;
