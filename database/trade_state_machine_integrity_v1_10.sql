-- Agro-Exchange v1.10 central trade state-machine integrity.
-- This trigger is a final database guard behind the role-specific RPCs.

create or replace function public.enforce_trade_status_transition_v1_10()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_allowed boolean:=false;
  v_due numeric(16,2);
  v_confirmed numeric(16,2);
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  -- Terminal states never reopen.
  if old.status in ('settled','cancelled') then
    raise exception 'Terminal trade state cannot transition: % -> %',old.status,new.status;
  end if;

  v_allowed:=case
    when old.status='confirmed'
      and new.status in ('awaiting_qc','ready_for_dispatch','disputed') then true
    when old.status='awaiting_qc'
      and new.status in ('ready_for_dispatch','disputed') then true
    when old.status='ready_for_dispatch'
      and new.status in ('in_transit','disputed') then true
    when old.status='in_transit'
      and new.status in ('ready_for_dispatch','delivered','disputed') then true
    when old.status='delivered'
      and new.status in ('disputed','settled') then true
    when old.status='disputed'
      and new.status in (
        'confirmed','awaiting_qc','ready_for_dispatch','in_transit',
        'delivered','settled','cancelled'
      ) then true
    else false
  end;

  if not v_allowed then
    raise exception 'Illegal trade state transition: % -> %',old.status,new.status;
  end if;

  if new.status='awaiting_qc' then
    if not exists(
      select 1
      from public.trade_confirmations tc
      where tc.trade_id=new.id and coalesce(tc.qc_required,true)=true
    ) then
      raise exception 'Trade cannot await QC unless QC is required';
    end if;
  end if;

  if new.status='in_transit' then
    if not exists(
      select 1
      from public.shipments s
      where s.trade_id=new.id and s.status='in_transit'
    ) then
      raise exception 'Trade cannot enter transit without an in-transit shipment';
    end if;
  end if;

  if new.status='delivered' then
    if not exists(
      select 1
      from public.shipments s
      where s.trade_id=new.id and s.status='delivered'
    ) then
      raise exception 'Trade cannot be delivered without a delivered shipment';
    end if;
  end if;

  if old.status='in_transit' and new.status='ready_for_dispatch' then
    if exists(
      select 1
      from public.shipments s
      where s.trade_id=new.id and s.status='in_transit'
    ) then
      raise exception 'Trade cannot return to dispatch while a shipment remains in transit';
    end if;
  end if;

  if new.status='settled' then
    select po.amount_due_bdt into v_due
    from public.payment_obligations po
    where po.trade_id=new.id and po.status='paid'
    limit 1;

    if v_due is null then
      raise exception 'Trade cannot settle without a paid payment obligation';
    end if;

    select round(coalesce(sum(p.amount_bdt),0),2) into v_confirmed
    from public.payments p
    where p.trade_id=new.id and p.status='confirmed';

    if v_confirmed<>v_due then
      raise exception 'Trade cannot settle unless confirmed payments equal amount due';
    end if;

    if exists(
      select 1
      from public.trade_disputes d
      where d.trade_id=new.id and d.status in ('open','proposal_pending')
    ) then
      raise exception 'Trade cannot settle with an active dispute';
    end if;
  end if;

  if new.status='cancelled' then
    if exists(
      select 1 from public.shipments s
      where s.trade_id=new.id and s.status in ('in_transit','delivered')
    ) or exists(
      select 1 from public.delivery_receipts dr where dr.trade_id=new.id
    ) then
      raise exception 'Trade cannot be cancelled after dispatch or delivery';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trade_status_transition_guard_v1_10 on public.trades;

create trigger trade_status_transition_guard_v1_10
before update of status on public.trades
for each row
execute function public.enforce_trade_status_transition_v1_10();

revoke all on function public.enforce_trade_status_transition_v1_10()
from public,anon,authenticated,service_role;
