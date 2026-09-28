-- Agro-Exchange v1.10 cancellation/inventory integrity hardening.
-- Inventory may be restored only while goods have not entered transit or delivery.
-- The helper remains idempotent and internal-only.

create or replace function public.restore_trade_inventory_after_cancel(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_trade public.trades%rowtype;
  v_match public.matches%rowtype;
  v_live_shipment_count integer;
begin
  select * into v_trade
  from public.trades
  where id=p_trade_id
  for update;

  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status<>'cancelled' then
    raise exception 'Inventory restoration requires a cancelled trade';
  end if;

  if exists(
    select 1
    from public.trade_status_events e
    where e.trade_id=p_trade_id
      and e.metadata->>'event_type'='inventory_restored_after_cancellation'
  ) then
    return;
  end if;

  if exists(
    select 1
    from public.shipments s
    where s.trade_id=p_trade_id
      and s.status in ('in_transit','delivered')
  ) or exists(
    select 1
    from public.delivery_receipts dr
    where dr.trade_id=p_trade_id
  ) then
    raise exception 'Inventory cannot be restored after dispatch or delivery';
  end if;

  update public.shipments
  set status='cancelled',
      cancelled_at=coalesce(cancelled_at,now()),
      cancellation_reason=coalesce(
        nullif(cancellation_reason,''),
        'Trade cancelled by mutually accepted commercial resolution'
      )
  where trade_id=p_trade_id
    and status in ('assigned','accepted');

  if v_trade.match_id is null then return; end if;

  select * into v_match
  from public.matches
  where id=v_trade.match_id;

  if not found then return; end if;

  update public.sell_offers so
  set remaining_quantity_kg=least(
        so.quantity_kg,
        so.remaining_quantity_kg+v_trade.agreed_quantity_kg
      ),
      status=case
        when so.status='cancelled' then 'cancelled'::public.order_status
        when so.available_until is not null and so.available_until<current_date
          then 'closed'::public.order_status
        when least(so.quantity_kg,so.remaining_quantity_kg+v_trade.agreed_quantity_kg)>=so.quantity_kg
          then 'open'::public.order_status
        else 'partially_matched'::public.order_status
      end,
      updated_at=now()
  where so.id=v_match.sell_offer_id;

  update public.buy_orders bo
  set remaining_quantity_kg=least(
        bo.quantity_kg,
        bo.remaining_quantity_kg+v_trade.agreed_quantity_kg
      ),
      status=case
        when bo.status='cancelled' then 'cancelled'::public.order_status
        when bo.delivery_until is not null and bo.delivery_until<current_date
          then 'closed'::public.order_status
        when least(bo.quantity_kg,bo.remaining_quantity_kg+v_trade.agreed_quantity_kg)>=bo.quantity_kg
          then 'open'::public.order_status
        else 'partially_matched'::public.order_status
      end,
      updated_at=now()
  where bo.id=v_match.buy_order_id;

  insert into public.trade_status_events(trade_id,status,metadata)
  values(
    v_trade.id,'cancelled',
    jsonb_build_object(
      'event_type','inventory_restored_after_cancellation',
      'sell_offer_id',v_match.sell_offer_id,
      'buy_order_id',v_match.buy_order_id,
      'restored_quantity_kg',v_trade.agreed_quantity_kg
    )
  );
end;
$$;

revoke all on function public.restore_trade_inventory_after_cancel(uuid)
from public,anon,authenticated,service_role;
