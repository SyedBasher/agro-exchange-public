-- Agro-Exchange buyer demand workflow RPCs
-- Applied to the live Supabase project in v0.8.
-- Buyer self-registration is intentionally NOT enabled. A signed-in profile must
-- already be approved as role=buyer and linked to a buyer organization.

create or replace function post_buy_order(
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
  v_role user_role;
  v_buyer_org_id uuid;
  v_commodity_id uuid;
  v_grade_id uuid;
  v_location_id uuid;
  v_order_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select id,role into v_profile_id,v_role
  from profiles
  where auth_user_id=auth.uid()
  limit 1;

  if v_profile_id is null then
    raise exception 'No Agro-Exchange profile is linked to this account';
  end if;

  if v_role <> 'buyer' then
    raise exception 'Only approved buyer accounts can post demand';
  end if;

  select buyer_organization_id into v_buyer_org_id
  from buyer_memberships
  where profile_id=v_profile_id
  order by buyer_organization_id
  limit 1;

  if v_buyer_org_id is null then
    raise exception 'Buyer account is not linked to an organization';
  end if;

  if p_quantity_kg is null or p_quantity_kg<=0 then
    raise exception 'Quantity must be greater than zero';
  end if;
  if p_target_price is not null and p_target_price<0 then
    raise exception 'Target price cannot be negative';
  end if;
  if p_delivery_from is null then
    raise exception 'Delivery start date is required';
  end if;
  if p_delivery_until is not null and p_delivery_until<p_delivery_from then
    raise exception 'Delivery end date cannot be before delivery start date';
  end if;

  select id into v_commodity_id
  from commodities
  where upper(code)=upper(p_commodity_code) and active=true
  limit 1;
  if v_commodity_id is null then
    raise exception 'Commodity not found: %',p_commodity_code;
  end if;

  select id into v_location_id
  from locations
  where lower(district)=lower(p_destination_district)
  order by (market_name is not null) desc,created_at asc
  limit 1;
  if v_location_id is null then
    raise exception 'Destination district not found: %',p_destination_district;
  end if;

  if p_grade_code is not null and btrim(p_grade_code)<>'' then
    select id into v_grade_id
    from commodity_grades
    where commodity_id=v_commodity_id and upper(code)=upper(p_grade_code)
    limit 1;
  end if;

  insert into buy_orders(
    buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,
    quantity_kg,remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
  ) values (
    v_buyer_org_id,v_profile_id,v_commodity_id,v_grade_id,v_location_id,
    p_quantity_kg,p_quantity_kg,p_target_price,p_delivery_from,p_delivery_until,'open'
  ) returning id into v_order_id;

  return v_order_id;
end;
$$;

revoke all on function post_buy_order(text,text,text,numeric,numeric,date,date) from public,anon;
grant execute on function post_buy_order(text,text,text,numeric,numeric,date,date) to authenticated;

create or replace function get_buy_order_matches(p_buy_order_id uuid)
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from buy_orders bo
    join buyer_memberships bm on bm.buyer_organization_id=bo.buyer_organization_id
    where bo.id=p_buy_order_id and bm.profile_id=current_profile_id()
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
    case lower(mc.origin_district)
      when 'bogra' then 3.50::numeric
      when 'rangpur' then 4.20::numeric
      when 'joypurhat' then 3.90::numeric
      else 4.00::numeric
    end as estimated_route_cost_bdt_per_kg,
    mc.earliest_feasible_date,
    mc.seller_verified,
    greatest(0::numeric,least(100::numeric,
      55
      + 5*(mc.gross_price_room_bdt_per_kg-
        case lower(mc.origin_district)
          when 'bogra' then 3.50::numeric
          when 'rangpur' then 4.20::numeric
          when 'joypurhat' then 3.90::numeric
          else 4.00::numeric
        end)
      + case when mc.seller_verified then 10 else 0 end
    )) as match_score
  from matching_candidates_view mc
  where mc.buy_order_id=p_buy_order_id
  order by match_score desc,mc.seller_floor_bdt_per_kg asc;
end;
$$;

revoke all on function get_buy_order_matches(uuid) from public,anon;
grant execute on function get_buy_order_matches(uuid) to authenticated;
