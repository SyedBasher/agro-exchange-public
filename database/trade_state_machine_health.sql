-- Agro-Exchange v1.10 trade state-machine health audit
-- READ ONLY. Returns anomaly counts only; safe for staging diagnostics.

with anomaly_counts as (
  select 'confirmed_no_qc_should_have_routed'::text as anomaly,
         count(*)::bigint as anomaly_count
  from public.trades t
  join public.trade_confirmations tc on tc.trade_id=t.id
  where t.status='confirmed' and coalesce(tc.qc_required,true)=false

  union all
  select 'awaiting_qc_without_qc_required',
         count(*)::bigint
  from public.trades t
  left join public.trade_confirmations tc on tc.trade_id=t.id
  where t.status='awaiting_qc'
    and coalesce(tc.qc_required,true)=false

  union all
  select 'in_transit_without_in_transit_shipment',
         count(*)::bigint
  from public.trades t
  where t.status='in_transit'
    and not exists(
      select 1 from public.shipments s
      where s.trade_id=t.id and s.status='in_transit'
    )

  union all
  select 'delivered_without_delivered_shipment',
         count(*)::bigint
  from public.trades t
  where t.status='delivered'
    and not exists(
      select 1 from public.shipments s
      where s.trade_id=t.id and s.status='delivered'
    )

  union all
  select 'settled_without_paid_obligation',
         count(*)::bigint
  from public.trades t
  where t.status='settled'
    and not exists(
      select 1 from public.payment_obligations po
      where po.trade_id=t.id and po.status='paid'
    )

  union all
  select 'settled_payment_total_mismatch',
         count(*)::bigint
  from public.trades t
  join public.payment_obligations po on po.trade_id=t.id
  where t.status='settled'
    and round(coalesce((
      select sum(p.amount_bdt)
      from public.payments p
      where p.trade_id=t.id and p.status='confirmed'
    ),0),2)<>po.amount_due_bdt

  union all
  select 'terminal_trade_with_active_dispute',
         count(*)::bigint
  from public.trades t
  where t.status in ('settled','cancelled')
    and exists(
      select 1 from public.trade_disputes d
      where d.trade_id=t.id and d.status in ('open','proposal_pending')
    )

  union all
  select 'cancelled_trade_with_live_or_delivered_shipment',
         count(*)::bigint
  from public.trades t
  where t.status='cancelled'
    and exists(
      select 1 from public.shipments s
      where s.trade_id=t.id and s.status in ('assigned','accepted','in_transit','delivered')
    )

  union all
  select 'disputed_without_active_or_system_dispute_basis',
         count(*)::bigint
  from public.trades t
  where t.status='disputed'
    and not exists(
      select 1 from public.trade_disputes d
      where d.trade_id=t.id and d.status in ('open','proposal_pending')
    )
    and not exists(
      select 1 from public.trade_status_events e
      where e.trade_id=t.id
        and e.status='disputed'
        and e.metadata->>'event_type' in ('qc_rejected','qc_failed','buyer_receipt_disputed')
    )
)
select anomaly,anomaly_count
from anomaly_counts
order by anomaly;
