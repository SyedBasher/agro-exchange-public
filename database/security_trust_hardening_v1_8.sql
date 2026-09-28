-- Agro-Exchange v1.8 — security, trust and matching hardening
-- Addresses Claude forensic audit Round 1 findings F-01/F-02/F-04/F-05/F-06/F-12/F-13/F-21/F-22/F-23/F-26/F-28.
-- Historical migrations are intentionally left unchanged; this migration defines the current production posture.

begin;

-- -----------------------------------------------------------------------------
-- 1. Close direct-write privilege escalation and inventory mutation paths.
-- -----------------------------------------------------------------------------

-- Profiles are created by the auth trigger and access/roles are administered only
-- through controlled RPCs. Normal users must never be able to PATCH role/verified.
revoke insert, update, delete on table public.profiles from authenticated;

-- Farms contain a trust flag too. No current browser workflow needs direct farm
-- mutation, so keep them read-only until a dedicated RPC is introduced.
revoke insert, update, delete on table public.farms from authenticated;

-- Supply and demand inventory are RPC-owned. Direct client writes could otherwise
-- resurrect closed orders or rewrite remaining quantity after a trade.
revoke insert, update, delete on table public.sell_offers from authenticated;
revoke insert, update, delete on table public.buy_orders from authenticated;

-- RLS policies call these pure caller-context helpers. They must be callable by the
-- authenticated role even though they remain SECURITY DEFINER with a fixed search_path.
grant execute on function public.current_profile_id() to authenticated;
grant execute on function public.current_user_role() to authenticated;

-- Safe self-service profile preferences. Commercial role and verification are not
-- parameters and therefore cannot be changed through this function.
create or replace function public.update_my_profile_preferences(
  p_display_name text default null,
  p_preferred_language text default null
)
returns table(profile_id uuid, display_name text, preferred_language text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_name text;
  v_language text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_profile
  from public.profiles
  where auth_user_id=auth.uid()
  for update;

  if not found then
    raise exception 'Profile not found';
  end if;

  v_name := coalesce(nullif(btrim(coalesce(p_display_name,'')),''),v_profile.display_name);
  v_language := coalesce(nullif(btrim(coalesce(p_preferred_language,'')),''),v_profile.preferred_language);

  if v_language not in ('bn','en') then
    raise exception 'Preferred language must be bn or en';
  end if;
  if char_length(v_name)>120 then
    raise exception 'Display name is too long';
  end if;

  update public.profiles
  set display_name=v_name,
      preferred_language=v_language,
      updated_at=now()
  where id=v_profile.id;

  return query
  select p.id,p.display_name,p.preferred_language
  from public.profiles p
  where p.id=v_profile.id;
end;
$$;

revoke all on function public.update_my_profile_preferences(text,text) from public,anon;
grant execute on function public.update_my_profile_preferences(text,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 2. One named, explicitly indicative fulfilment allowance.
--    This is NOT represented as an observed transport/QC/platform cost decomposition.
-- -----------------------------------------------------------------------------

create or replace function public.indicative_fulfilment_allowance_bdt_per_kg(
  p_origin_district text,
  p_destination_district text
)
returns numeric
language sql
immutable
set search_path=public
as $$
  select case lower(coalesce(p_origin_district,''))
    when 'bogra' then 3.50::numeric
    when 'rangpur' then 4.20::numeric
    when 'joypurhat' then 3.90::numeric
    else 4.00::numeric
  end;
$$;

grant execute on function public.indicative_fulfilment_allowance_bdt_per_kg(text,text) to anon,authenticated;

-- -----------------------------------------------------------------------------
-- 3. Verified supply and economically feasible matching only.
-- -----------------------------------------------------------------------------

create or replace view public.open_supply_view as
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
  and p.verified=true;

create or replace view public.matching_candidates_view as
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
  d.target_price_bdt_per_kg-s.minimum_price_bdt_per_kg-public.indicative_fulfilment_allowance_bdt_per_kg(s.origin_district,d.destination_district) as net_price_room_bdt_per_kg,
  least(s.remaining_quantity_kg,d.remaining_quantity_kg)/nullif(s.remaining_quantity_kg,0) as seller_quantity_coverage,
  least(s.remaining_quantity_kg,d.remaining_quantity_kg)/nullif(d.remaining_quantity_kg,0) as buyer_quantity_coverage
from public.open_supply_view s
join public.open_demand_view d
  on d.commodity_code=s.commodity_code
 and (
      d.grade_code is null
      or (s.grade_code is not null and s.grade_code=d.grade_code)
 )
where greatest(s.available_from,d.delivery_from)
      <=least(coalesce(s.available_until,'9999-12-31'::date),coalesce(d.delivery_until,'9999-12-31'::date))
  and s.minimum_price_bdt_per_kg is not null
  and d.target_price_bdt_per_kg is not null
  and s.minimum_price_bdt_per_kg>0
  and d.target_price_bdt_per_kg>0
  and d.target_price_bdt_per_kg-s.minimum_price_bdt_per_kg
      >=public.indicative_fulfilment_allowance_bdt_per_kg(s.origin_district,d.destination_district);

-- Seller-side query. Rank by real, explainable components; the numeric score is kept
-- only for backwards compatibility and is not intended as the user-facing rationale.
create or replace function public.get_sell_offer_matches(p_sell_offer_id uuid)
returns table(
  sell_offer_id uuid,
  buy_order_id uuid,
  commodity_code text,
  origin_district text,
  destination_district text,
  feasible_quantity_kg numeric,
  seller_floor_bdt_per_kg numeric,
  buyer_target_bdt_per_kg numeric,
  gross_price_room_bdt_per_kg numeric,
  estimated_route_cost_bdt_per_kg numeric,
  earliest_feasible_date date,
  buyer_name text,
  buyer_verified boolean,
  match_score numeric
)
language plpgsql
security definer
set search_path=public
as $$
declare v_owner uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select so.seller_profile_id into v_owner
  from public.sell_offers so
  where so.id=p_sell_offer_id;
  if v_owner is null or v_owner<>public.current_profile_id() then
    raise exception 'Offer not found or not owned by current user';
  end if;

  return query
  select
    mc.sell_offer_id,
    mc.buy_order_id,
    mc.commodity_code,
    mc.origin_district,
    mc.destination_district,
    mc.feasible_quantity_kg,
    mc.seller_floor_bdt_per_kg,
    mc.buyer_target_bdt_per_kg,
    mc.gross_price_room_bdt_per_kg,
    mc.indicative_fulfilment_allowance_bdt_per_kg,
    mc.earliest_feasible_date,
    mc.buyer_name,
    mc.buyer_verified,
    round(100*(0.60*least(1::numeric,mc.net_price_room_bdt_per_kg/greatest(mc.indicative_fulfilment_allowance_bdt_per_kg,1::numeric))
                  +0.40*mc.seller_quantity_coverage),1) as match_score
  from public.matching_candidates_view mc
  where mc.sell_offer_id=p_sell_offer_id
  order by mc.net_price_room_bdt_per_kg desc,
           mc.seller_quantity_coverage desc,
           mc.earliest_feasible_date asc,
           mc.buy_order_id asc;
end;
$$;

revoke all on function public.get_sell_offer_matches(uuid) from public,anon;
grant execute on function public.get_sell_offer_matches(uuid) to authenticated;

-- Buyer-side query uses buyer-order coverage rather than seller-offer coverage.
create or replace function public.get_buy_order_matches(p_buy_order_id uuid)
returns table(
  buy_order_id uuid,
  sell_offer_id uuid,
  commodity_code text,
  origin_district text,
  destination_district text,
  feasible_quantity_kg numeric,
  seller_floor_bdt_per_kg numeric,
  buyer_target_bdt_per_kg numeric,
  gross_price_room_bdt_per_kg numeric,
  estimated_route_cost_bdt_per_kg numeric,
  earliest_feasible_date date,
  seller_verified boolean,
  match_score numeric
)
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  if not exists(
    select 1
    from public.buy_orders bo
    join public.buyer_memberships bm on bm.buyer_organization_id=bo.buyer_organization_id
    where bo.id=p_buy_order_id and bm.profile_id=public.current_profile_id()
  ) then
    raise exception 'Order not found or not owned by current buyer';
  end if;

  return query
  select
    mc.buy_order_id,
    mc.sell_offer_id,
    mc.commodity_code,
    mc.origin_district,
    mc.destination_district,
    mc.feasible_quantity_kg,
    mc.seller_floor_bdt_per_kg,
    mc.buyer_target_bdt_per_kg,
    mc.gross_price_room_bdt_per_kg,
    mc.indicative_fulfilment_allowance_bdt_per_kg,
    mc.earliest_feasible_date,
    mc.seller_verified,
    round(100*(0.60*least(1::numeric,mc.net_price_room_bdt_per_kg/greatest(mc.indicative_fulfilment_allowance_bdt_per_kg,1::numeric))
                  +0.40*mc.buyer_quantity_coverage),1) as match_score
  from public.matching_candidates_view mc
  where mc.buy_order_id=p_buy_order_id
  order by mc.net_price_room_bdt_per_kg desc,
           mc.buyer_quantity_coverage desc,
           mc.earliest_feasible_date asc,
           mc.sell_offer_id asc;
end;
$$;

revoke all on function public.get_buy_order_matches(uuid) from public,anon;
grant execute on function public.get_buy_order_matches(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4. Stronger posting rules and seller verification symmetry.
-- -----------------------------------------------------------------------------

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
  v_profile_id uuid;
  v_role public.user_role;
  v_verified boolean;
  v_commodity_id uuid;
  v_grade_id uuid;
  v_location_id uuid;
  v_offer_id uuid;
  v_fulfilment text;
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

  select id into v_commodity_id from public.commodities
  where upper(code)=upper(p_commodity_code) and active=true limit 1;
  if v_commodity_id is null then raise exception 'Commodity not found: %',p_commodity_code; end if;

  select id into v_location_id from public.locations
  where lower(district)=lower(p_origin_district)
  order by (market_name is not null) desc,created_at asc limit 1;
  if v_location_id is null then raise exception 'Origin district not found: %',p_origin_district; end if;

  if p_grade_code is not null and btrim(p_grade_code)<>'' then
    select id into v_grade_id from public.commodity_grades
    where commodity_id=v_commodity_id and upper(code)=upper(p_grade_code) limit 1;
    if v_grade_id is null then raise exception 'Grade is not valid for this commodity'; end if;
  end if;

  insert into public.sell_offers(
    seller_profile_id,commodity_id,grade_id,origin_location_id,quantity_kg,
    remaining_quantity_kg,minimum_price_bdt_per_kg,available_from,
    fulfilment_preference,status
  ) values(
    v_profile_id,v_commodity_id,v_grade_id,v_location_id,p_quantity_kg,
    p_quantity_kg,p_minimum_price,p_available_from,v_fulfilment,'open'
  ) returning id into v_offer_id;

  return v_offer_id;
end;
$$;

revoke all on function public.post_sell_offer(text,text,text,numeric,numeric,date,text) from public,anon;
grant execute on function public.post_sell_offer(text,text,text,numeric,numeric,date,text) to authenticated;

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
  v_profile_id uuid;
  v_role public.user_role;
  v_profile_verified boolean;
  v_buyer_org_id uuid;
  v_commodity_id uuid;
  v_grade_id uuid;
  v_location_id uuid;
  v_order_id uuid;
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
  if p_delivery_until is not null and p_delivery_until<p_delivery_from then raise exception 'Delivery end date cannot be before delivery start date'; end if;

  select id into v_commodity_id from public.commodities
  where upper(code)=upper(p_commodity_code) and active=true limit 1;
  if v_commodity_id is null then raise exception 'Commodity not found: %',p_commodity_code; end if;

  select id into v_location_id from public.locations
  where lower(district)=lower(p_destination_district)
  order by (market_name is not null) desc,created_at asc limit 1;
  if v_location_id is null then raise exception 'Destination district not found: %',p_destination_district; end if;

  if p_grade_code is not null and btrim(p_grade_code)<>'' then
    select id into v_grade_id from public.commodity_grades
    where commodity_id=v_commodity_id and upper(code)=upper(p_grade_code) limit 1;
    if v_grade_id is null then raise exception 'Grade is not valid for this commodity'; end if;
  end if;

  insert into public.buy_orders(
    buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,
    quantity_kg,remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
  ) values(
    v_buyer_org_id,v_profile_id,v_commodity_id,v_grade_id,v_location_id,
    p_quantity_kg,p_quantity_kg,p_target_price,p_delivery_from,p_delivery_until,'open'
  ) returning id into v_order_id;

  return v_order_id;
end;
$$;

revoke all on function public.post_buy_order(text,text,text,numeric,numeric,date,date) from public,anon;
grant execute on function public.post_buy_order(text,text,text,numeric,numeric,date,date) to authenticated;

-- Trade proposals remain negotiable, but a zero/negative commercial price is never valid.
-- Require the seller to still be verified when a new transaction is proposed/accepted.
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
  v_profile public.profiles%rowtype;
  v_sell public.sell_offers%rowtype;
  v_buy public.buy_orders%rowtype;
  v_is_seller boolean:=false;
  v_is_buyer boolean:=false;
  v_confirmation public.trade_confirmations%rowtype;
  v_ref text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_quantity_kg is null or p_quantity_kg<=0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_price_bdt_per_kg is null or p_price_bdt_per_kg<=0 then raise exception 'Price must be greater than zero'; end if;

  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_sell from public.sell_offers where id=p_sell_offer_id for update;
  if not found or v_sell.status not in ('open','matched','partially_matched') then raise exception 'Sell offer is not available'; end if;
  select * into v_buy from public.buy_orders where id=p_buy_order_id for update;
  if not found or v_buy.status not in ('open','matched','partially_matched') then raise exception 'Buy order is not available'; end if;

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
  if p_quantity_kg>least(v_sell.remaining_quantity_kg,v_buy.remaining_quantity_kg) then raise exception 'Quantity exceeds remaining available amount'; end if;

  v_is_seller:=v_sell.seller_profile_id=v_profile.id;
  v_is_buyer:=v_profile.role='buyer' and v_profile.verified and exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_buy.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then raise exception 'You are not a participant in this potential trade'; end if;

  v_ref:='AX-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.trade_confirmations(
    reference,sell_offer_id,buy_order_id,seller_profile_id,buyer_organization_id,commodity_id,
    grade_id,origin_location_id,destination_location_id,agreed_quantity_kg,agreed_price_bdt_per_kg,
    delivery_due_at,payment_terms,qc_required,proposed_by_profile_id,
    seller_accepted_at,seller_accepted_by,buyer_accepted_at,buyer_accepted_by,status,expires_at
  ) values(
    v_ref,v_sell.id,v_buy.id,v_sell.seller_profile_id,v_buy.buyer_organization_id,v_sell.commodity_id,
    coalesce(v_sell.grade_id,v_buy.grade_id),v_sell.origin_location_id,v_buy.destination_location_id,
    p_quantity_kg,p_price_bdt_per_kg,p_delivery_due_at,nullif(trim(p_payment_terms),''),coalesce(p_qc_required,true),v_profile.id,
    case when v_is_seller then now() end,case when v_is_seller then v_profile.id end,
    case when v_is_buyer then now() end,case when v_is_buyer then v_profile.id end,
    case when v_is_seller then 'seller_accepted' else 'buyer_accepted' end,
    now()+interval '48 hours'
  ) returning * into v_confirmation;

  return query select v_confirmation.id,v_confirmation.reference,v_confirmation.status,
    v_confirmation.seller_accepted_at is not null,v_confirmation.buyer_accepted_at is not null;
end;
$$;

revoke all on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) from public,anon;
grant execute on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) to authenticated;

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
  v_profile public.profiles%rowtype;
  v_c public.trade_confirmations%rowtype;
  v_sell public.sell_offers%rowtype;
  v_buy public.buy_orders%rowtype;
  v_is_seller boolean:=false;
  v_is_buyer boolean:=false;
  v_match_id uuid;
  v_trade_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_c from public.trade_confirmations where id=p_confirmation_id for update;
  if not found then raise exception 'Trade confirmation not found'; end if;
  if v_c.status in ('confirmed','declined','expired') then raise exception 'Trade confirmation is no longer open'; end if;
  if v_c.expires_at is not null and v_c.expires_at<now() then
    update public.trade_confirmations set status='expired',updated_at=now() where id=v_c.id;
    raise exception 'Trade confirmation has expired';
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
    select * into v_sell from public.sell_offers where id=v_c.sell_offer_id for update;
    select * into v_buy from public.buy_orders where id=v_c.buy_order_id for update;
    if v_sell.remaining_quantity_kg<v_c.agreed_quantity_kg or v_buy.remaining_quantity_kg<v_c.agreed_quantity_kg then
      raise exception 'Available quantity changed before confirmation';
    end if;

    insert into public.matches(
      sell_offer_id,buy_order_id,matched_quantity_kg,proposed_price_bdt_per_kg,status,score,scoring_version,scoring_factors
    ) values(
      v_c.sell_offer_id,v_c.buy_order_id,v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,'converted',null,
      'trade-confirmation-v1.8',jsonb_build_object('confirmation_reference',v_c.reference)
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
      values(v_trade_id,'confirmed',v_profile.id,jsonb_build_object('confirmation_reference',v_c.reference,'qc_required',v_c.qc_required));
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

revoke all on function public.accept_trade_confirmation(uuid) from public,anon;
grant execute on function public.accept_trade_confirmation(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. Commercial acceptance stays with commercial parties; admin is oversight.
-- -----------------------------------------------------------------------------

create or replace function public.initiate_trade_payment(
  p_trade_id uuid,
  p_method text,
  p_external_reference text,
  p_amount_bdt numeric,
  p_notes text default null
)
returns table(payment_id uuid,payment_status text,amount_bdt numeric,remaining_due_bdt numeric)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trades%rowtype;
  v_obligation public.payment_obligations%rowtype;
  v_payment public.payments%rowtype;
  v_confirmed numeric(16,2);
  v_remaining numeric(16,2);
  v_is_buyer boolean:=false;
  v_method text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_is_buyer:=exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id
  );
  if not v_is_buyer then raise exception 'Buyer organization must record payment initiation'; end if;

  select * into v_obligation from public.payment_obligations where trade_id=p_trade_id for update;
  if not found or v_obligation.status in ('pending_receipt','disputed','paid') then raise exception 'Payment is not currently due'; end if;
  if not exists(select 1 from public.delivery_receipts where trade_id=p_trade_id and status='accepted') then
    raise exception 'Buyer receipt acceptance is required before payment initiation';
  end if;
  if exists(select 1 from public.payments where trade_id=p_trade_id and status='initiated') then
    raise exception 'An initiated payment is already awaiting seller confirmation';
  end if;
  if p_amount_bdt is null or p_amount_bdt<=0 then raise exception 'Payment amount must be greater than zero'; end if;

  v_method:=lower(trim(coalesce(p_method,'')));
  if v_method not in ('bank_transfer','mobile_financial_service','cash','other') then raise exception 'Unsupported payment method'; end if;
  if v_method<>'cash' and nullif(trim(coalesce(p_external_reference,'')),'') is null then
    raise exception 'Payment reference is required for non-cash payments';
  end if;

  select coalesce(sum(amount_bdt),0) into v_confirmed from public.payments where trade_id=p_trade_id and status='confirmed';
  v_remaining:=greatest(v_obligation.amount_due_bdt-v_confirmed,0);
  if p_amount_bdt>v_remaining+0.01 then raise exception 'Payment amount exceeds remaining amount due'; end if;

  insert into public.payments(
    trade_id,payment_obligation_id,method,external_reference,amount_bdt,status,
    initiated_at,recorded_by_profile_id,notes,updated_at
  ) values(
    p_trade_id,v_obligation.id,v_method,nullif(trim(coalesce(p_external_reference,'')),''),round(p_amount_bdt,2),
    'initiated',now(),v_profile.id,nullif(trim(coalesce(p_notes,'')),''),now()
  ) returning * into v_payment;

  update public.payment_obligations set status='initiated',updated_at=now() where id=v_obligation.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(p_trade_id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_initiated','payment_id',v_payment.id,'method',v_method,'amount_bdt',v_payment.amount_bdt));

  return query select v_payment.id,v_payment.status::text,v_payment.amount_bdt,greatest(v_remaining-v_payment.amount_bdt,0);
end;
$$;

revoke all on function public.initiate_trade_payment(uuid,text,text,numeric,text) from public,anon;
grant execute on function public.initiate_trade_payment(uuid,text,text,numeric,text) to authenticated;

create or replace function public.confirm_trade_payment(p_payment_id uuid,p_notes text default null)
returns table(payment_id uuid,payment_status text,obligation_status text,trade_status text,total_confirmed_bdt numeric,amount_due_bdt numeric)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_payment public.payments%rowtype;
  v_trade public.trades%rowtype;
  v_obligation public.payment_obligations%rowtype;
  v_total numeric(16,2);
  v_obligation_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found then raise exception 'Payment record not found'; end if;
  if v_payment.status<>'initiated' then raise exception 'Only initiated payments can be confirmed'; end if;
  select * into v_trade from public.trades where id=v_payment.trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status='disputed' or exists(
    select 1 from public.trade_disputes d where d.trade_id=v_trade.id and d.status in ('open','proposal_pending')
  ) then raise exception 'Resolve the active dispute before confirming payment'; end if;

  if v_trade.seller_profile_id<>v_profile.id then raise exception 'Seller must confirm payment receipt'; end if;

  select * into v_obligation from public.payment_obligations where id=v_payment.payment_obligation_id for update;
  if not found then raise exception 'Payment obligation not found'; end if;

  update public.payments
  set status='confirmed',confirmed_at=now(),confirmed_by_profile_id=v_profile.id,
      notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),updated_at=now()
  where id=v_payment.id;

  select coalesce(sum(amount_bdt),0) into v_total from public.payments where trade_id=v_trade.id and status='confirmed';
  if v_total+0.01>=v_obligation.amount_due_bdt then
    v_obligation_status:='paid';
    update public.payment_obligations set status='paid',updated_at=now() where id=v_obligation.id;
    update public.trades set status='settled',settled_at=now(),updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'settled',v_profile.id,jsonb_build_object('event_type','payment_fully_confirmed','payment_id',v_payment.id,'total_confirmed_bdt',v_total,'amount_due_bdt',v_obligation.amount_due_bdt));
  else
    v_obligation_status:='partially_paid';
    update public.payment_obligations set status='partially_paid',updated_at=now() where id=v_obligation.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_partially_confirmed','payment_id',v_payment.id,'total_confirmed_bdt',v_total,'amount_due_bdt',v_obligation.amount_due_bdt));
  end if;

  return query select v_payment.id,'confirmed'::text,v_obligation_status,
    (select t.status::text from public.trades t where t.id=v_trade.id),v_total,v_obligation.amount_due_bdt;
end;
$$;

revoke all on function public.confirm_trade_payment(uuid,text) from public,anon;
grant execute on function public.confirm_trade_payment(uuid,text) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. QC telemetry ownership and shipment uniqueness backstop.
-- -----------------------------------------------------------------------------

create or replace function public.record_qc_telemetry(
  p_qc_record_id uuid,
  p_inspection_level text,
  p_direct_cost_bdt numeric,
  p_inspection_reason text default null
)
returns table(qc_record_id uuid,inspection_level text,direct_cost_bdt numeric,inspection_reason text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_q public.qc_records%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator or admin access required'; end if;
  if p_inspection_level not in ('basic','independent','enhanced') then raise exception 'Inspection level must be basic, independent or enhanced'; end if;
  if p_direct_cost_bdt is null or p_direct_cost_bdt<0 then raise exception 'Direct QC cost cannot be negative'; end if;
  select * into v_q from public.qc_records where id=p_qc_record_id for update;
  if not found then raise exception 'QC record not found'; end if;
  if v_profile.role='qc_operator' and v_q.operator_profile_id<>v_profile.id then
    raise exception 'QC operators can record telemetry only for their own inspection records';
  end if;

  update public.qc_records
  set inspection_level=p_inspection_level,
      direct_cost_bdt=p_direct_cost_bdt,
      inspection_reason=nullif(btrim(coalesce(p_inspection_reason,'')),''),
      telemetry_recorded_at=now(),
      telemetry_recorded_by_profile_id=v_profile.id
  where id=p_qc_record_id;

  return query select p_qc_record_id,p_inspection_level,p_direct_cost_bdt,
    nullif(btrim(coalesce(p_inspection_reason,'')),'');
end;
$$;

revoke all on function public.record_qc_telemetry(uuid,text,numeric,text) from public,anon;
grant execute on function public.record_qc_telemetry(uuid,text,numeric,text) to authenticated;

create unique index if not exists shipments_one_active_per_trade_idx
  on public.shipments(trade_id)
  where status in ('assigned','accepted','in_transit');

commit;
