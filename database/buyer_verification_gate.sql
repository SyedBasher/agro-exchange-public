-- Agro-Exchange v1.4: make buyer/profile verification operationally meaningful.
-- Unverified buyer organizations must not post new demand or enter new trade confirmations.
-- Historical/ongoing fulfilment and dispute workflows remain available so obligations can be resolved.

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
  from public.profiles
  where auth_user_id=auth.uid()
  limit 1;

  if v_profile_id is null then raise exception 'No Agro-Exchange profile is linked to this account'; end if;
  if v_role<>'buyer' or not coalesce(v_profile_verified,false) then
    raise exception 'Only verified buyer accounts can post demand';
  end if;

  select bm.buyer_organization_id into v_buyer_org_id
  from public.buyer_memberships bm
  join public.buyer_organizations org on org.id=bm.buyer_organization_id and org.verified=true
  where bm.profile_id=v_profile_id
  order by bm.buyer_organization_id
  limit 1;

  if v_buyer_org_id is null then raise exception 'Buyer account is not linked to a verified organization'; end if;

  if p_quantity_kg is null or p_quantity_kg<=0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_target_price is not null and p_target_price<0 then raise exception 'Target price cannot be negative'; end if;
  if p_delivery_from is null then raise exception 'Delivery start date is required'; end if;
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
  end if;

  insert into public.buy_orders(
    buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,
    quantity_kg,remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
  ) values (
    v_buyer_org_id,v_profile_id,v_commodity_id,v_grade_id,v_location_id,
    p_quantity_kg,p_quantity_kg,p_target_price,p_delivery_from,p_delivery_until,'open'
  ) returning id into v_order_id;

  return v_order_id;
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
returns table(confirmation_id uuid,confirmation_reference text,confirmation_status text,seller_accepted boolean,buyer_accepted boolean)
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
  if p_price_bdt_per_kg is null or p_price_bdt_per_kg<0 then raise exception 'Price is not valid'; end if;

  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  select * into v_sell from public.sell_offers where id=p_sell_offer_id for update;
  if not found or v_sell.status not in ('open','matched','partially_matched') then raise exception 'Sell offer is not available'; end if;

  select * into v_buy from public.buy_orders where id=p_buy_order_id for update;
  if not found or v_buy.status not in ('open','matched','partially_matched') then raise exception 'Buy order is not available'; end if;

  if not exists(select 1 from public.buyer_organizations org where org.id=v_buy.buyer_organization_id and org.verified=true) then
    raise exception 'Buyer organization is not currently verified for new trades';
  end if;

  if v_sell.commodity_id<>v_buy.commodity_id then raise exception 'Commodity mismatch'; end if;
  if v_sell.grade_id is not null and v_buy.grade_id is not null and v_sell.grade_id<>v_buy.grade_id then raise exception 'Grade mismatch'; end if;
  if p_quantity_kg>least(v_sell.remaining_quantity_kg,v_buy.remaining_quantity_kg) then raise exception 'Quantity exceeds remaining available amount'; end if;

  v_is_seller:=v_sell.seller_profile_id=v_profile.id;
  v_is_buyer:=v_profile.role='buyer' and v_profile.verified and exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_buy.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then raise exception 'You are not a participant in this potential trade'; end if;

  v_ref:='AX-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.trade_confirmations(
    reference,sell_offer_id,buy_order_id,seller_profile_id,buyer_organization_id,commodity_id,grade_id,
    origin_location_id,destination_location_id,agreed_quantity_kg,agreed_price_bdt_per_kg,delivery_due_at,
    payment_terms,qc_required,proposed_by_profile_id,seller_accepted_at,seller_accepted_by,buyer_accepted_at,
    buyer_accepted_by,status,expires_at
  ) values (
    v_ref,v_sell.id,v_buy.id,v_sell.seller_profile_id,v_buy.buyer_organization_id,v_sell.commodity_id,
    coalesce(v_sell.grade_id,v_buy.grade_id),v_sell.origin_location_id,v_buy.destination_location_id,
    p_quantity_kg,p_price_bdt_per_kg,p_delivery_due_at,nullif(trim(p_payment_terms),''),coalesce(p_qc_required,true),
    v_profile.id,case when v_is_seller then now() end,case when v_is_seller then v_profile.id end,
    case when v_is_buyer then now() end,case when v_is_buyer then v_profile.id end,
    case when v_is_seller then 'seller_accepted' else 'buyer_accepted' end,now()+interval '48 hours'
  ) returning * into v_confirmation;

  return query select v_confirmation.id,v_confirmation.reference,v_confirmation.status,
    v_confirmation.seller_accepted_at is not null,v_confirmation.buyer_accepted_at is not null;
end;
$$;

create or replace function public.accept_trade_confirmation(p_confirmation_id uuid)
returns table(confirmation_id uuid,confirmation_reference text,confirmation_status text,trade_id uuid,trade_status text)
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

    insert into public.matches(sell_offer_id,buy_order_id,matched_quantity_kg,proposed_price_bdt_per_kg,status,score,scoring_version,scoring_factors)
    values(v_c.sell_offer_id,v_c.buy_order_id,v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,'converted',null,'trade-confirmation-v0.9',jsonb_build_object('confirmation_reference',v_c.reference))
    returning id into v_match_id;

    insert into public.trades(match_id,seller_profile_id,buyer_organization_id,commodity_id,grade_id,origin_location_id,destination_location_id,agreed_quantity_kg,agreed_price_bdt_per_kg,delivery_due_at,payment_terms,status)
    values(v_match_id,v_c.seller_profile_id,v_c.buyer_organization_id,v_c.commodity_id,v_c.grade_id,v_c.origin_location_id,v_c.destination_location_id,v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,v_c.delivery_due_at,v_c.payment_terms,'confirmed')
    returning id into v_trade_id;

    update public.trade_confirmations set status='confirmed',trade_id=v_trade_id,updated_at=now() where id=v_c.id;
    update public.sell_offers set remaining_quantity_kg=remaining_quantity_kg-v_c.agreed_quantity_kg,
      status=case when remaining_quantity_kg-v_c.agreed_quantity_kg<=0 then 'closed'::public.order_status else 'partially_matched'::public.order_status end,updated_at=now()
      where id=v_c.sell_offer_id;
    update public.buy_orders set remaining_quantity_kg=remaining_quantity_kg-v_c.agreed_quantity_kg,
      status=case when remaining_quantity_kg-v_c.agreed_quantity_kg<=0 then 'closed'::public.order_status else 'partially_matched'::public.order_status end,updated_at=now()
      where id=v_c.buy_order_id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade_id,'confirmed',v_profile.id,jsonb_build_object('confirmation_reference',v_c.reference,'qc_required',v_c.qc_required));
  else
    update public.trade_confirmations set status=case when seller_accepted_at is not null then 'seller_accepted' else 'buyer_accepted' end,updated_at=now() where id=v_c.id;
  end if;

  select * into v_c from public.trade_confirmations where id=p_confirmation_id;
  return query select v_c.id,v_c.reference,v_c.status,v_c.trade_id,
    case when v_c.trade_id is not null then (select t.status::text from public.trades t where t.id=v_c.trade_id) else null end;
end;
$$;

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
  and org.verified=true;

revoke all on function public.post_buy_order(text,text,text,numeric,numeric,date,date) from public,anon;
revoke all on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) from public,anon;
revoke all on function public.accept_trade_confirmation(uuid) from public,anon;
grant execute on function public.post_buy_order(text,text,text,numeric,numeric,date,date) to authenticated;
grant execute on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) to authenticated;
grant execute on function public.accept_trade_confirmation(uuid) to authenticated;
