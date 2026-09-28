-- Agro-Exchange v1.2: buyer receipt confirmation and payment-status/settlement workflow
-- The platform records payment state and references; it does not hold, escrow or move funds.

create table if not exists public.delivery_receipts (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null unique references public.trades(id) on delete cascade,
  shipment_id uuid not null unique references public.shipments(id) on delete cascade,
  buyer_organization_id uuid not null references public.buyer_organizations(id),
  confirmed_by_profile_id uuid not null references public.profiles(id),
  received_quantity_kg numeric(14,2) check (received_quantity_kg is null or received_quantity_kg > 0),
  status text not null check (status in ('accepted','disputed')),
  notes text,
  discrepancy_reason text,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.payment_obligations (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null unique references public.trades(id) on delete cascade,
  buyer_organization_id uuid not null references public.buyer_organizations(id),
  basis_quantity_kg numeric(14,2) not null check (basis_quantity_kg > 0),
  unit_price_bdt_per_kg numeric(12,2) not null check (unit_price_bdt_per_kg >= 0),
  amount_due_bdt numeric(16,2) not null check (amount_due_bdt >= 0),
  status text not null default 'pending_receipt' check (status in ('pending_receipt','due','initiated','partially_paid','paid','disputed')),
  due_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.payments add column if not exists payment_obligation_id uuid references public.payment_obligations(id);
alter table public.payments add column if not exists recorded_by_profile_id uuid references public.profiles(id);
alter table public.payments add column if not exists confirmed_by_profile_id uuid references public.profiles(id);
alter table public.payments add column if not exists notes text;
alter table public.payments add column if not exists updated_at timestamptz not null default now();

create index if not exists delivery_receipts_buyer_idx on public.delivery_receipts (buyer_organization_id, confirmed_at desc);
create index if not exists payment_obligations_status_idx on public.payment_obligations (status, updated_at desc);
create index if not exists payments_trade_status_idx on public.payments (trade_id, status, created_at desc);
create index if not exists payments_obligation_idx on public.payments (payment_obligation_id, status, created_at desc);

alter table public.delivery_receipts enable row level security;
alter table public.payment_obligations enable row level security;

-- Participants may read their own receipt/settlement data. Workflow writes go through checked RPCs.
drop policy if exists delivery_receipts_participant_read on public.delivery_receipts;
create policy delivery_receipts_participant_read on public.delivery_receipts
for select to authenticated
using (
  exists (
    select 1 from public.trades t
    where t.id=delivery_receipts.trade_id
      and (
        t.seller_profile_id=(select id from public.profiles where auth_user_id=auth.uid())
        or exists (
          select 1 from public.buyer_memberships bm
          join public.profiles p on p.id=bm.profile_id
          where p.auth_user_id=auth.uid() and bm.buyer_organization_id=t.buyer_organization_id
        )
        or exists (select 1 from public.profiles p where p.auth_user_id=auth.uid() and p.role='admin')
      )
  )
);

drop policy if exists payment_obligations_participant_read on public.payment_obligations;
create policy payment_obligations_participant_read on public.payment_obligations
for select to authenticated
using (
  exists (
    select 1 from public.trades t
    where t.id=payment_obligations.trade_id
      and (
        t.seller_profile_id=(select id from public.profiles where auth_user_id=auth.uid())
        or exists (
          select 1 from public.buyer_memberships bm
          join public.profiles p on p.id=bm.profile_id
          where p.auth_user_id=auth.uid() and bm.buyer_organization_id=t.buyer_organization_id
        )
        or exists (select 1 from public.profiles p where p.auth_user_id=auth.uid() and p.role='admin')
      )
  )
);

revoke insert,update,delete on public.delivery_receipts from anon,authenticated;
revoke insert,update,delete on public.payment_obligations from anon,authenticated;
revoke insert,update,delete on public.payments from anon,authenticated;
grant select on public.delivery_receipts,public.payment_obligations,public.payments to authenticated;

create or replace function public.confirm_delivery_receipt(
  p_trade_id uuid,
  p_received_quantity_kg numeric default null,
  p_accepted boolean default true,
  p_notes text default null,
  p_discrepancy_reason text default null
)
returns table(receipt_id uuid, receipt_status text, obligation_id uuid, amount_due_bdt numeric, trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trades%rowtype;
  v_shipment public.shipments%rowtype;
  v_receipt public.delivery_receipts%rowtype;
  v_obligation public.payment_obligations%rowtype;
  v_is_buyer boolean := false;
  v_amount numeric(16,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status <> 'delivered' then raise exception 'Trade must be delivered before buyer receipt confirmation'; end if;

  v_is_buyer := exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id
  );
  if not (v_is_buyer or v_profile.role='admin') then raise exception 'Buyer organization or admin access required'; end if;

  if p_received_quantity_kg is not null and p_received_quantity_kg <= 0 then raise exception 'Received quantity must be greater than zero'; end if;
  if not coalesce(p_accepted,true) and nullif(trim(coalesce(p_discrepancy_reason,'')),'') is null then
    raise exception 'Discrepancy reason is required when delivery is disputed';
  end if;
  if exists(select 1 from public.delivery_receipts where trade_id=p_trade_id) then
    raise exception 'Delivery receipt has already been recorded for this trade';
  end if;

  select * into v_shipment from public.shipments
  where trade_id=p_trade_id and status='delivered'
  order by delivered_at desc nulls last, created_at desc limit 1;
  if not found then raise exception 'Delivered shipment not found'; end if;

  insert into public.delivery_receipts(
    trade_id,shipment_id,buyer_organization_id,confirmed_by_profile_id,received_quantity_kg,status,notes,discrepancy_reason
  ) values (
    v_trade.id,v_shipment.id,v_trade.buyer_organization_id,v_profile.id,p_received_quantity_kg,
    case when coalesce(p_accepted,true) then 'accepted' else 'disputed' end,
    nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_discrepancy_reason,'')),'')
  ) returning * into v_receipt;

  v_amount := round(v_trade.agreed_quantity_kg * v_trade.agreed_price_bdt_per_kg,2);

  insert into public.payment_obligations(
    trade_id,buyer_organization_id,basis_quantity_kg,unit_price_bdt_per_kg,amount_due_bdt,status,due_at
  ) values (
    v_trade.id,v_trade.buyer_organization_id,v_trade.agreed_quantity_kg,v_trade.agreed_price_bdt_per_kg,v_amount,
    case when v_receipt.status='accepted' then 'due' else 'disputed' end,
    case when v_receipt.status='accepted' then now() else null end
  ) returning * into v_obligation;

  if v_receipt.status='disputed' then
    update public.trades set status='disputed',updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade.id,'disputed',v_profile.id,jsonb_build_object('event_type','buyer_receipt_disputed','receipt_id',v_receipt.id,'reason',v_receipt.discrepancy_reason));
  else
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade.id,'delivered',v_profile.id,jsonb_build_object('event_type','buyer_receipt_accepted','receipt_id',v_receipt.id,'payment_obligation_id',v_obligation.id,'amount_due_bdt',v_amount));
  end if;

  return query select v_receipt.id,v_receipt.status,v_obligation.id,v_obligation.amount_due_bdt,
    (select t.status::text from public.trades t where t.id=v_trade.id);
end;
$$;

create or replace function public.initiate_trade_payment(
  p_trade_id uuid,
  p_method text,
  p_external_reference text,
  p_amount_bdt numeric,
  p_notes text default null
)
returns table(payment_id uuid, payment_status text, amount_bdt numeric, remaining_due_bdt numeric)
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
  v_is_buyer boolean := false;
  v_method text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_is_buyer := exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id);
  if not (v_is_buyer or v_profile.role='admin') then raise exception 'Buyer organization or admin access required'; end if;

  select * into v_obligation from public.payment_obligations where trade_id=p_trade_id for update;
  if not found or v_obligation.status in ('pending_receipt','disputed','paid') then raise exception 'Payment is not currently due'; end if;
  if not exists(select 1 from public.delivery_receipts where trade_id=p_trade_id and status='accepted') then raise exception 'Buyer receipt acceptance is required before payment initiation'; end if;

  if p_amount_bdt is null or p_amount_bdt <= 0 then raise exception 'Payment amount must be greater than zero'; end if;
  v_method := lower(trim(coalesce(p_method,'')));
  if v_method not in ('bank_transfer','mobile_financial_service','cash','other') then raise exception 'Unsupported payment method'; end if;
  if v_method <> 'cash' and nullif(trim(coalesce(p_external_reference,'')),'') is null then raise exception 'Payment reference is required for non-cash payments'; end if;

  select coalesce(sum(amount_bdt),0) into v_confirmed from public.payments where trade_id=p_trade_id and status='confirmed';
  v_remaining := greatest(v_obligation.amount_due_bdt-v_confirmed,0);
  if p_amount_bdt > v_remaining + 0.01 then raise exception 'Payment amount exceeds remaining amount due'; end if;

  insert into public.payments(
    trade_id,payment_obligation_id,method,external_reference,amount_bdt,status,initiated_at,recorded_by_profile_id,notes,updated_at
  ) values (
    p_trade_id,v_obligation.id,v_method,nullif(trim(coalesce(p_external_reference,'')),''),round(p_amount_bdt,2),'initiated',now(),v_profile.id,nullif(trim(coalesce(p_notes,'')),''),now()
  ) returning * into v_payment;

  update public.payment_obligations set status='initiated',updated_at=now() where id=v_obligation.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(p_trade_id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_initiated','payment_id',v_payment.id,'method',v_method,'amount_bdt',v_payment.amount_bdt));

  return query select v_payment.id,v_payment.status::text,v_payment.amount_bdt,greatest(v_remaining-v_payment.amount_bdt,0);
end;
$$;

create or replace function public.confirm_trade_payment(
  p_payment_id uuid,
  p_notes text default null
)
returns table(payment_id uuid, payment_status text, obligation_status text, trade_status text, total_confirmed_bdt numeric, amount_due_bdt numeric)
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
  if v_payment.status <> 'initiated' then raise exception 'Only initiated payments can be confirmed'; end if;

  select * into v_trade from public.trades where id=v_payment.trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if not (v_trade.seller_profile_id=v_profile.id or v_profile.role='admin') then raise exception 'Seller or admin confirmation required'; end if;
  select * into v_obligation from public.payment_obligations where id=v_payment.payment_obligation_id for update;
  if not found then raise exception 'Payment obligation not found'; end if;

  update public.payments set status='confirmed',confirmed_at=now(),confirmed_by_profile_id=v_profile.id,
    notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),updated_at=now()
  where id=v_payment.id;

  select coalesce(sum(amount_bdt),0) into v_total from public.payments where trade_id=v_trade.id and status='confirmed';

  if v_total + 0.01 >= v_obligation.amount_due_bdt then
    v_obligation_status := 'paid';
    update public.payment_obligations set status='paid',updated_at=now() where id=v_obligation.id;
    update public.trades set status='settled',settled_at=now(),updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade.id,'settled',v_profile.id,jsonb_build_object('event_type','payment_fully_confirmed','payment_id',v_payment.id,'total_confirmed_bdt',v_total,'amount_due_bdt',v_obligation.amount_due_bdt));
  else
    v_obligation_status := 'partially_paid';
    update public.payment_obligations set status='partially_paid',updated_at=now() where id=v_obligation.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade.id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_partially_confirmed','payment_id',v_payment.id,'total_confirmed_bdt',v_total,'amount_due_bdt',v_obligation.amount_due_bdt));
  end if;

  return query select v_payment.id,'confirmed'::text,v_obligation_status,
    (select t.status::text from public.trades t where t.id=v_trade.id),v_total,v_obligation.amount_due_bdt;
end;
$$;

create or replace function public.mark_trade_payment_failed(
  p_payment_id uuid,
  p_reason text
)
returns table(payment_id uuid, payment_status text, obligation_status text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_payment public.payments%rowtype;
  v_trade public.trades%rowtype;
  v_obligation public.payment_obligations%rowtype;
  v_confirmed numeric(16,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Failure reason is required'; end if;

  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found or v_payment.status <> 'initiated' then raise exception 'Initiated payment not found'; end if;
  select * into v_trade from public.trades where id=v_payment.trade_id;
  if not found then raise exception 'Trade not found'; end if;

  if not (
    v_profile.role='admin' or v_trade.seller_profile_id=v_profile.id or exists(
      select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id
    )
  ) then raise exception 'Trade participant or admin access required'; end if;

  update public.payments set status='failed',notes=concat_ws(' | ',notes,'Failed: '||trim(p_reason)),updated_at=now() where id=v_payment.id;
  select * into v_obligation from public.payment_obligations where id=v_payment.payment_obligation_id for update;
  select coalesce(sum(amount_bdt),0) into v_confirmed from public.payments where trade_id=v_trade.id and status='confirmed';
  update public.payment_obligations set status=case when v_confirmed>0 then 'partially_paid' else 'due' end,updated_at=now() where id=v_obligation.id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_failed','payment_id',v_payment.id,'reason',trim(p_reason)));

  return query select v_payment.id,'failed'::text,case when v_confirmed>0 then 'partially_paid' else 'due' end;
end;
$$;

create or replace function public.get_my_settlements()
returns table(
  trade_id uuid, confirmation_reference text, trade_status text,
  commodity_code text, commodity_name_en text, commodity_name_bn text,
  origin_district text, destination_district text,
  agreed_quantity_kg numeric, agreed_price_bdt_per_kg numeric,
  receipt_status text, received_quantity_kg numeric, receipt_confirmed_at timestamptz,
  obligation_id uuid, amount_due_bdt numeric, obligation_status text,
  total_confirmed_bdt numeric, remaining_due_bdt numeric,
  latest_payment_id uuid, latest_payment_status text, latest_payment_method text, latest_payment_reference text,
  is_seller boolean, is_buyer boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  return query
  select t.id,tc.reference,t.status::text,c.code,c.name_en,c.name_bn,lo.district,ld.district,
    t.agreed_quantity_kg,t.agreed_price_bdt_per_kg,dr.status,dr.received_quantity_kg,dr.confirmed_at,
    po.id,po.amount_due_bdt,po.status,
    coalesce(pay.confirmed_total,0),greatest(coalesce(po.amount_due_bdt,0)-coalesce(pay.confirmed_total,0),0),
    lp.id,lp.status::text,lp.method,lp.external_reference,
    t.seller_profile_id=v_profile.id,
    exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id)
  from public.trades t
  left join public.trade_confirmations tc on tc.trade_id=t.id
  join public.commodities c on c.id=t.commodity_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.delivery_receipts dr on dr.trade_id=t.id
  left join public.payment_obligations po on po.trade_id=t.id
  left join lateral (
    select coalesce(sum(p.amount_bdt) filter(where p.status='confirmed'),0) as confirmed_total
    from public.payments p where p.trade_id=t.id
  ) pay on true
  left join lateral (
    select p.id,p.status,p.method,p.external_reference from public.payments p
    where p.trade_id=t.id order by p.created_at desc limit 1
  ) lp on true
  where t.status in ('delivered','settled','disputed')
    and (
      v_profile.role='admin'
      or t.seller_profile_id=v_profile.id
      or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id)
    )
  order by t.updated_at desc,t.created_at desc;
end;
$$;

revoke all on function public.confirm_delivery_receipt(uuid,numeric,boolean,text,text) from public,anon;
revoke all on function public.initiate_trade_payment(uuid,text,text,numeric,text) from public,anon;
revoke all on function public.confirm_trade_payment(uuid,text) from public,anon;
revoke all on function public.mark_trade_payment_failed(uuid,text) from public,anon;
revoke all on function public.get_my_settlements() from public,anon;
grant execute on function public.confirm_delivery_receipt(uuid,numeric,boolean,text,text) to authenticated;
grant execute on function public.initiate_trade_payment(uuid,text,text,numeric,text) to authenticated;
grant execute on function public.confirm_trade_payment(uuid,text) to authenticated;
grant execute on function public.mark_trade_payment_failed(uuid,text) to authenticated;
grant execute on function public.get_my_settlements() to authenticated;
