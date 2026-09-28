-- Agro-Exchange Supabase RPCs for the first persistent seller workflow.
-- Apply after schema.sql, views.sql and supabase_security.sql.

create or replace function post_sell_offer(
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
  v_role user_role;
  v_commodity_id uuid;
  v_grade_id uuid;
  v_location_id uuid;
  v_offer_id uuid;
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

  if v_role not in ('farmer','admin') then
    raise exception 'Only farmer accounts can post supply in this workflow';
  end if;

  if p_quantity_kg is null or p_quantity_kg<=0 then
    raise exception 'Quantity must be greater than zero';
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
  where lower(district)=lower(p_origin_district)
  order by (market_name is not null) desc,created_at asc
  limit 1;

  if v_location_id is null then
    raise exception 'Origin district not found: %',p_origin_district;
  end if;

  if p_grade_code is not null and btrim(p_grade_code)<>'' then
    select id into v_grade_id
    from commodity_grades
    where commodity_id=v_commodity_id and upper(code)=upper(p_grade_code)
    limit 1;
  end if;

  insert into sell_offers(
    seller_profile_id,commodity_id,grade_id,origin_location_id,
    quantity_kg,remaining_quantity_kg,minimum_price_bdt_per_kg,
    available_from,fulfilment_preference,status
  ) values (
    v_profile_id,v_commodity_id,v_grade_id,v_location_id,
    p_quantity_kg,p_quantity_kg,p_minimum_price,
    p_available_from,coalesce(nullif(p_fulfilment_preference,''),'collection_base'),'open'
  ) returning id into v_offer_id;

  return v_offer_id;
end;
$$;

revoke all on function post_sell_offer(text,text,text,numeric,numeric,date,text) from public;
grant execute on function post_sell_offer(text,text,text,numeric,numeric,date,text) to authenticated;

create or replace function get_sell_offer_matches(p_sell_offer_id uuid)
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
declare
  v_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select so.seller_profile_id into v_owner
  from sell_offers so
  where so.id=p_sell_offer_id;

  if v_owner is null or v_owner<>current_profile_id() then
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
    case lower(mc.origin_district)
      when 'bogra' then 3.50::numeric
      when 'rangpur' then 4.20::numeric
      when 'joypurhat' then 3.90::numeric
      else 4.00::numeric
    end as estimated_route_cost_bdt_per_kg,
    mc.earliest_feasible_date,
    mc.buyer_name,
    mc.buyer_verified,
    greatest(0::numeric,least(100::numeric,
      55
      + 5*(mc.gross_price_room_bdt_per_kg-
        case lower(mc.origin_district)
          when 'bogra' then 3.50::numeric
          when 'rangpur' then 4.20::numeric
          when 'joypurhat' then 3.90::numeric
          else 4.00::numeric
        end)
      + case when mc.buyer_verified then 10 else 0 end
    )) as match_score
  from matching_candidates_view mc
  where mc.sell_offer_id=p_sell_offer_id
  order by match_score desc,mc.buyer_target_bdt_per_kg desc;
end;
$$;

revoke all on function get_sell_offer_matches(uuid) from public;
grant execute on function get_sell_offer_matches(uuid) to authenticated;
