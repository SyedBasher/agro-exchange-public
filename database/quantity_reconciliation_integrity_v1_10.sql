-- Agro-Exchange v1.10 quantity reconciliation and relational integrity.
-- Defense-in-depth invariants for commercial quantity/payment linkage.

create or replace function public.enforce_trade_adjustment_quantity_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_trade public.trades%rowtype;
begin
  if new.resolution_type in ('revise_terms','partial_rejection') then
    select t.* into v_trade
    from public.trade_disputes d
    join public.trades t on t.id=d.trade_id
    where d.id=new.dispute_id;

    if not found then
      raise exception 'Adjustment dispute is not linked to a trade';
    end if;

    if new.proposed_quantity_kg is null or new.proposed_quantity_kg<=0 then
      raise exception 'Adjusted quantity must be greater than zero';
    end if;

    if new.proposed_quantity_kg>v_trade.agreed_quantity_kg then
      raise exception 'Adjusted quantity cannot exceed the originally reserved trade quantity';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trade_adjustment_quantity_integrity_v1_10
on public.trade_adjustment_proposals;

create trigger trade_adjustment_quantity_integrity_v1_10
before insert or update of dispute_id,resolution_type,proposed_quantity_kg
on public.trade_adjustment_proposals
for each row
execute function public.enforce_trade_adjustment_quantity_integrity();

create or replace function public.enforce_payment_trade_obligation_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_obligation public.payment_obligations%rowtype;
begin
  select * into v_obligation
  from public.payment_obligations
  where id=new.payment_obligation_id;

  if not found then
    raise exception 'Payment obligation not found';
  end if;

  if v_obligation.trade_id<>new.trade_id then
    raise exception 'Payment trade does not match its payment obligation';
  end if;

  return new;
end;
$$;

drop trigger if exists payment_trade_obligation_integrity_v1_10
on public.payments;

create trigger payment_trade_obligation_integrity_v1_10
before insert or update of trade_id,payment_obligation_id
on public.payments
for each row
execute function public.enforce_payment_trade_obligation_integrity();

create or replace function public.enforce_delivery_receipt_link_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_shipment public.shipments%rowtype;
  v_trade public.trades%rowtype;
begin
  select * into v_shipment
  from public.shipments
  where id=new.shipment_id;

  if not found then raise exception 'Receipt shipment not found'; end if;
  if v_shipment.trade_id<>new.trade_id then
    raise exception 'Delivery receipt trade does not match its shipment';
  end if;

  select * into v_trade
  from public.trades
  where id=new.trade_id;

  if not found then raise exception 'Receipt trade not found'; end if;
  if v_trade.buyer_organization_id<>new.buyer_organization_id then
    raise exception 'Delivery receipt buyer organization does not match the trade';
  end if;

  return new;
end;
$$;

drop trigger if exists delivery_receipt_link_integrity_v1_10
on public.delivery_receipts;

create trigger delivery_receipt_link_integrity_v1_10
before insert or update of trade_id,shipment_id,buyer_organization_id
on public.delivery_receipts
for each row
execute function public.enforce_delivery_receipt_link_integrity();

revoke all on function public.enforce_trade_adjustment_quantity_integrity()
from public,anon,authenticated,service_role;
revoke all on function public.enforce_payment_trade_obligation_integrity()
from public,anon,authenticated,service_role;
revoke all on function public.enforce_delivery_receipt_link_integrity()
from public,anon,authenticated,service_role;
