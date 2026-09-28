-- Agro-Exchange v0.9: two-party Digital Trade Confirmation
-- A trade is created only after both seller and buyer accept the same terms.

create table if not exists public.trade_confirmations (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  sell_offer_id uuid not null references public.sell_offers(id),
  buy_order_id uuid not null references public.buy_orders(id),
  seller_profile_id uuid not null references public.profiles(id),
  buyer_organization_id uuid not null references public.buyer_organizations(id),
  commodity_id uuid not null references public.commodities(id),
  grade_id uuid references public.commodity_grades(id),
  origin_location_id uuid not null references public.locations(id),
  destination_location_id uuid not null references public.locations(id),
  agreed_quantity_kg numeric(14,2) not null check (agreed_quantity_kg > 0),
  agreed_price_bdt_per_kg numeric(12,2) not null check (agreed_price_bdt_per_kg >= 0),
  delivery_due_at timestamptz,
  payment_terms text,
  qc_required boolean not null default true,
  proposed_by_profile_id uuid not null references public.profiles(id),
  seller_accepted_at timestamptz,
  seller_accepted_by uuid references public.profiles(id),
  buyer_accepted_at timestamptz,
  buyer_accepted_by uuid references public.profiles(id),
  status text not null default 'proposed' check (status in ('proposed','seller_accepted','buyer_accepted','confirmed','declined','expired')),
  trade_id uuid unique references public.trades(id),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists trade_confirmations_party_idx
  on public.trade_confirmations (seller_profile_id, buyer_organization_id, status, created_at desc);
create index if not exists trade_confirmations_pair_idx
  on public.trade_confirmations (sell_offer_id, buy_order_id, created_at desc);

alter table public.trade_confirmations enable row level security;

drop policy if exists trade_confirmations_participant_select on public.trade_confirmations;
create policy trade_confirmations_participant_select
on public.trade_confirmations for select
to authenticated
using (
  seller_profile_id = (select id from public.profiles where auth_user_id = auth.uid())
  or exists (
    select 1
    from public.buyer_memberships bm
    join public.profiles p on p.id = bm.profile_id
    where p.auth_user_id = auth.uid()
      and bm.buyer_organization_id = trade_confirmations.buyer_organization_id
  )
);

revoke insert, update, delete on public.trade_confirmations from anon, authenticated;
grant select on public.trade_confirmations to authenticated;

create or replace function public.propose_trade_confirmation(
  p_sell_offer_id uuid,
  p_buy_order_id uuid,
  p_quantity_kg numeric,
  p_price_bdt_per_kg numeric,
  p_delivery_due_at timestamptz,
  p_payment_terms text default 'Payment after delivery confirmation',
  p_qc_required boolean default true
)
returns table(confirmation_id uuid, confirmation_reference text, confirmation_status text, seller_accepted boolean, buyer_accepted boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_sell public.sell_offers%rowtype;
  v_buy public.buy_orders%rowtype;
  v_is_seller boolean := false;
  v_is_buyer boolean := false;
  v_confirmation public.trade_confirmations%rowtype;
  v_ref text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_quantity_kg is null or p_quantity_kg <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if p_price_bdt_per_kg is null or p_price_bdt_per_kg < 0 then raise exception 'Price is not valid'; end if;

  select * into v_profile from public.profiles where auth_user_id = auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  select * into v_sell from public.sell_offers where id = p_sell_offer_id for update;
  if not found or v_sell.status not in ('open','matched','partially_matched') then raise exception 'Sell offer is not available'; end if;

  select * into v_buy from public.buy_orders where id = p_buy_order_id for update;
  if not found or v_buy.status not in ('open','matched','partially_matched') then raise exception 'Buy order is not available'; end if;

  if v_sell.commodity_id <> v_buy.commodity_id then raise exception 'Commodity mismatch'; end if;
  if v_sell.grade_id is not null and v_buy.grade_id is not null and v_sell.grade_id <> v_buy.grade_id then raise exception 'Grade mismatch'; end if;
  if p_quantity_kg > least(v_sell.remaining_quantity_kg, v_buy.remaining_quantity_kg) then raise exception 'Quantity exceeds remaining available amount'; end if;

  v_is_seller := v_sell.seller_profile_id = v_profile.id;
  v_is_buyer := exists (
    select 1 from public.buyer_memberships
    where profile_id = v_profile.id and buyer_organization_id = v_buy.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then raise exception 'You are not a participant in this potential trade'; end if;

  v_ref := 'AX-' || to_char(now(),'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

  insert into public.trade_confirmations(
    reference, sell_offer_id, buy_order_id, seller_profile_id, buyer_organization_id,
    commodity_id, grade_id, origin_location_id, destination_location_id,
    agreed_quantity_kg, agreed_price_bdt_per_kg, delivery_due_at, payment_terms,
    qc_required, proposed_by_profile_id,
    seller_accepted_at, seller_accepted_by, buyer_accepted_at, buyer_accepted_by,
    status, expires_at
  ) values (
    v_ref, v_sell.id, v_buy.id, v_sell.seller_profile_id, v_buy.buyer_organization_id,
    v_sell.commodity_id, coalesce(v_sell.grade_id,v_buy.grade_id), v_sell.origin_location_id, v_buy.destination_location_id,
    p_quantity_kg, p_price_bdt_per_kg, p_delivery_due_at, nullif(trim(p_payment_terms),''),
    coalesce(p_qc_required,true), v_profile.id,
    case when v_is_seller then now() end, case when v_is_seller then v_profile.id end,
    case when v_is_buyer then now() end, case when v_is_buyer then v_profile.id end,
    case when v_is_seller then 'seller_accepted' else 'buyer_accepted' end,
    now() + interval '48 hours'
  ) returning * into v_confirmation;

  return query select v_confirmation.id, v_confirmation.reference, v_confirmation.status,
    v_confirmation.seller_accepted_at is not null, v_confirmation.buyer_accepted_at is not null;
end;
$$;

create or replace function public.accept_trade_confirmation(p_confirmation_id uuid)
returns table(confirmation_id uuid, confirmation_reference text, confirmation_status text, trade_id uuid, trade_status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_c public.trade_confirmations%rowtype;
  v_sell public.sell_offers%rowtype;
  v_buy public.buy_orders%rowtype;
  v_is_seller boolean := false;
  v_is_buyer boolean := false;
  v_match_id uuid;
  v_trade_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id = auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  select * into v_c from public.trade_confirmations where id = p_confirmation_id for update;
  if not found then raise exception 'Trade confirmation not found'; end if;
  if v_c.status in ('confirmed','declined','expired') then raise exception 'Trade confirmation is no longer open'; end if;
  if v_c.expires_at is not null and v_c.expires_at < now() then
    update public.trade_confirmations set status='expired', updated_at=now() where id=v_c.id;
    raise exception 'Trade confirmation has expired';
  end if;

  v_is_seller := v_c.seller_profile_id = v_profile.id;
  v_is_buyer := exists (
    select 1 from public.buyer_memberships
    where profile_id = v_profile.id and buyer_organization_id = v_c.buyer_organization_id
  );
  if not (v_is_seller or v_is_buyer) then raise exception 'You are not a participant in this trade confirmation'; end if;

  if v_is_seller and v_c.seller_accepted_at is null then
    update public.trade_confirmations set seller_accepted_at=now(), seller_accepted_by=v_profile.id, updated_at=now() where id=v_c.id;
  end if;
  if v_is_buyer and v_c.buyer_accepted_at is null then
    update public.trade_confirmations set buyer_accepted_at=now(), buyer_accepted_by=v_profile.id, updated_at=now() where id=v_c.id;
  end if;

  select * into v_c from public.trade_confirmations where id=p_confirmation_id for update;

  if v_c.seller_accepted_at is not null and v_c.buyer_accepted_at is not null then
    select * into v_sell from public.sell_offers where id=v_c.sell_offer_id for update;
    select * into v_buy from public.buy_orders where id=v_c.buy_order_id for update;
    if v_sell.remaining_quantity_kg < v_c.agreed_quantity_kg or v_buy.remaining_quantity_kg < v_c.agreed_quantity_kg then
      raise exception 'Available quantity changed before confirmation';
    end if;

    insert into public.matches(
      sell_offer_id,buy_order_id,matched_quantity_kg,proposed_price_bdt_per_kg,status,score,scoring_version,scoring_factors
    ) values (
      v_c.sell_offer_id,v_c.buy_order_id,v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,'converted',null,'trade-confirmation-v0.9',jsonb_build_object('confirmation_reference',v_c.reference)
    ) returning id into v_match_id;

    insert into public.trades(
      match_id,seller_profile_id,buyer_organization_id,commodity_id,grade_id,origin_location_id,destination_location_id,
      agreed_quantity_kg,agreed_price_bdt_per_kg,delivery_due_at,payment_terms,status
    ) values (
      v_match_id,v_c.seller_profile_id,v_c.buyer_organization_id,v_c.commodity_id,v_c.grade_id,v_c.origin_location_id,v_c.destination_location_id,
      v_c.agreed_quantity_kg,v_c.agreed_price_bdt_per_kg,v_c.delivery_due_at,v_c.payment_terms,'confirmed'
    ) returning id into v_trade_id;

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

create or replace function public.get_my_trade_confirmations()
returns table(
  confirmation_id uuid, confirmation_reference text, confirmation_status text,
  commodity_code text, commodity_name_en text, commodity_name_bn text,
  origin_district text, destination_district text,
  agreed_quantity_kg numeric, agreed_price_bdt_per_kg numeric,
  delivery_due_at timestamptz, payment_terms text, qc_required boolean,
  seller_accepted boolean, buyer_accepted boolean, trade_id uuid, created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select tc.id,tc.reference,tc.status,c.code,c.name_en,c.name_bn,lo.district,ld.district,
    tc.agreed_quantity_kg,tc.agreed_price_bdt_per_kg,tc.delivery_due_at,tc.payment_terms,tc.qc_required,
    tc.seller_accepted_at is not null,tc.buyer_accepted_at is not null,tc.trade_id,tc.created_at
  from public.trade_confirmations tc
  join public.commodities c on c.id=tc.commodity_id
  join public.locations lo on lo.id=tc.origin_location_id
  join public.locations ld on ld.id=tc.destination_location_id
  where auth.uid() is not null
    and (
      tc.seller_profile_id=(select id from public.profiles where auth_user_id=auth.uid())
      or exists(
        select 1 from public.buyer_memberships bm
        join public.profiles p on p.id=bm.profile_id
        where p.auth_user_id=auth.uid() and bm.buyer_organization_id=tc.buyer_organization_id
      )
    )
  order by tc.created_at desc;
$$;

revoke all on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) from public, anon;
revoke all on function public.accept_trade_confirmation(uuid) from public, anon;
revoke all on function public.get_my_trade_confirmations() from public, anon;
grant execute on function public.propose_trade_confirmation(uuid,uuid,numeric,numeric,timestamptz,text,boolean) to authenticated;
grant execute on function public.accept_trade_confirmation(uuid) to authenticated;
grant execute on function public.get_my_trade_confirmations() to authenticated;
