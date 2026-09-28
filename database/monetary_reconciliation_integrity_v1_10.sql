-- Agro-Exchange v1.10 monetary reconciliation integrity.
-- Keeps all recorded amounts at the database's native 2-decimal precision.

alter table public.payments
  drop constraint if exists payments_amount_bdt_check;
alter table public.payments
  add constraint payments_amount_bdt_positive_v1_10
  check (amount_bdt>0);

alter table public.payment_obligations
  drop constraint if exists payment_obligations_unit_price_bdt_per_kg_check;
alter table public.payment_obligations
  add constraint payment_obligations_unit_price_positive_v1_10
  check (unit_price_bdt_per_kg>0);

create unique index if not exists payments_non_cash_reference_per_trade_v1_10
on public.payments(
  trade_id,
  lower(btrim(method)),
  lower(btrim(external_reference))
)
where lower(btrim(coalesce(method,'')))<>'cash'
  and nullif(btrim(coalesce(external_reference,'')),'') is not null;

create or replace function public.enforce_payment_obligation_amount_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_expected numeric(16,2);
begin
  v_expected:=round(new.basis_quantity_kg*new.unit_price_bdt_per_kg,2);

  if new.status='cancelled' then
    if new.amount_due_bdt<>0 then
      raise exception 'Cancelled payment obligation must have zero amount due';
    end if;
  elsif new.amount_due_bdt<>v_expected then
    raise exception 'Payment obligation amount must equal quantity multiplied by unit price';
  end if;

  return new;
end;
$$;

drop trigger if exists payment_obligation_amount_integrity_v1_10
on public.payment_obligations;

create trigger payment_obligation_amount_integrity_v1_10
before insert or update of basis_quantity_kg,unit_price_bdt_per_kg,amount_due_bdt,status
on public.payment_obligations
for each row
execute function public.enforce_payment_obligation_amount_integrity();

revoke all on function public.enforce_payment_obligation_amount_integrity()
from public,anon,authenticated,service_role;

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
  v_amount numeric(16,2);
  v_is_buyer boolean:=false;
  v_method text;
  v_reference text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_is_buyer:=v_profile.role='buyer'
    and v_profile.verified
    and exists(
      select 1
      from public.buyer_memberships bm
      join public.buyer_organizations org
        on org.id=bm.buyer_organization_id and org.verified=true
      where bm.profile_id=v_profile.id
        and bm.buyer_organization_id=v_trade.buyer_organization_id
    );

  if not v_is_buyer then
    raise exception 'Verified buyer organization must record payment initiation';
  end if;

  if v_trade.status='disputed'
     or exists(
       select 1 from public.trade_disputes d
       where d.trade_id=v_trade.id and d.status in ('open','proposal_pending')
     ) then
    raise exception 'Resolve the active dispute before initiating payment';
  end if;

  select * into v_obligation
  from public.payment_obligations
  where trade_id=p_trade_id
  for update;

  if not found or v_obligation.status in ('pending_receipt','disputed','paid','cancelled') then
    raise exception 'Payment is not currently due';
  end if;

  if not exists(
    select 1 from public.delivery_receipts
    where trade_id=p_trade_id and status='accepted'
  ) then
    raise exception 'Buyer receipt acceptance is required before payment initiation';
  end if;

  if exists(
    select 1 from public.payments
    where trade_id=p_trade_id and status='initiated'
  ) then
    raise exception 'An initiated payment is already awaiting seller confirmation';
  end if;

  v_amount:=round(p_amount_bdt,2);
  if p_amount_bdt is null or v_amount<=0 then
    raise exception 'Payment amount must be greater than zero';
  end if;

  v_method:=lower(btrim(coalesce(p_method,'')));
  if v_method not in ('bank_transfer','mobile_financial_service','cash','other') then
    raise exception 'Unsupported payment method';
  end if;

  v_reference:=nullif(btrim(coalesce(p_external_reference,'')),'');
  if v_method<>'cash' and v_reference is null then
    raise exception 'Payment reference is required for non-cash payments';
  end if;

  if v_method<>'cash' and exists(
    select 1
    from public.payments p
    where p.trade_id=p_trade_id
      and lower(btrim(p.method))=v_method
      and lower(btrim(p.external_reference))=lower(v_reference)
      and p.status in ('initiated','confirmed')
  ) then
    raise exception 'This payment reference has already been used for this trade';
  end if;

  select coalesce(sum(amount_bdt),0) into v_confirmed
  from public.payments
  where trade_id=p_trade_id and status='confirmed';

  v_confirmed:=round(v_confirmed,2);
  v_remaining:=round(v_obligation.amount_due_bdt-v_confirmed,2);

  if v_remaining<=0 then
    raise exception 'No payment amount remains due';
  end if;

  if v_amount>v_remaining then
    raise exception 'Payment amount exceeds remaining amount due';
  end if;

  insert into public.payments(
    trade_id,payment_obligation_id,method,external_reference,amount_bdt,status,
    initiated_at,recorded_by_profile_id,notes,updated_at
  ) values(
    p_trade_id,v_obligation.id,v_method,v_reference,v_amount,'initiated',
    now(),v_profile.id,nullif(btrim(coalesce(p_notes,'')),''),now()
  ) returning * into v_payment;

  update public.payment_obligations
  set status='initiated',updated_at=now()
  where id=v_obligation.id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(
    p_trade_id,'delivered',v_profile.id,
    jsonb_build_object(
      'event_type','payment_initiated',
      'payment_id',v_payment.id,
      'method',v_method,
      'amount_bdt',v_payment.amount_bdt
    )
  );

  return query
  select v_payment.id,v_payment.status::text,v_payment.amount_bdt,
         round(v_remaining-v_payment.amount_bdt,2);
end;
$$;

create or replace function public.confirm_trade_payment(
  p_payment_id uuid,
  p_notes text default null
)
returns table(
  payment_id uuid,payment_status text,obligation_status text,trade_status text,
  total_confirmed_bdt numeric,amount_due_bdt numeric
)
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
  if v_payment.status<>'initiated' then
    raise exception 'Only initiated payments can be confirmed';
  end if;

  select * into v_trade from public.trades where id=v_payment.trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  if v_trade.status='disputed'
     or exists(
       select 1 from public.trade_disputes d
       where d.trade_id=v_trade.id and d.status in ('open','proposal_pending')
     ) then
    raise exception 'Resolve the active dispute before confirming payment';
  end if;

  if v_trade.seller_profile_id<>v_profile.id then
    raise exception 'Seller must confirm payment receipt';
  end if;

  select * into v_obligation
  from public.payment_obligations
  where id=v_payment.payment_obligation_id
  for update;

  if not found then raise exception 'Payment obligation not found'; end if;
  if v_obligation.trade_id<>v_trade.id then
    raise exception 'Payment obligation does not belong to this trade';
  end if;
  if v_obligation.status in ('paid','cancelled','disputed') then
    raise exception 'Payment obligation cannot accept confirmation in its current state';
  end if;

  select round(coalesce(sum(amount_bdt),0)+v_payment.amount_bdt,2)
    into v_total
  from public.payments
  where trade_id=v_trade.id
    and status='confirmed';

  if v_total>v_obligation.amount_due_bdt then
    raise exception 'Confirmed payment total would exceed the amount due';
  end if;

  update public.payments
  set status='confirmed',
      confirmed_at=now(),
      confirmed_by_profile_id=v_profile.id,
      notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),
      updated_at=now()
  where id=v_payment.id;

  if v_total=v_obligation.amount_due_bdt then
    v_obligation_status:='paid';

    update public.payment_obligations
    set status='paid',updated_at=now()
    where id=v_obligation.id;

    update public.trades
    set status='settled',settled_at=now(),updated_at=now()
    where id=v_trade.id;

    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(
      v_trade.id,'settled',v_profile.id,
      jsonb_build_object(
        'event_type','payment_fully_confirmed',
        'payment_id',v_payment.id,
        'total_confirmed_bdt',v_total,
        'amount_due_bdt',v_obligation.amount_due_bdt
      )
    );
  else
    v_obligation_status:='partially_paid';

    update public.payment_obligations
    set status='partially_paid',updated_at=now()
    where id=v_obligation.id;

    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(
      v_trade.id,'delivered',v_profile.id,
      jsonb_build_object(
        'event_type','payment_partially_confirmed',
        'payment_id',v_payment.id,
        'total_confirmed_bdt',v_total,
        'amount_due_bdt',v_obligation.amount_due_bdt
      )
    );
  end if;

  return query
  select v_payment.id,'confirmed'::text,v_obligation_status,
         (select t.status::text from public.trades t where t.id=v_trade.id),
         v_total,v_obligation.amount_due_bdt;
end;
$$;

revoke all on function public.initiate_trade_payment(uuid,text,text,numeric,text)
from public,anon;
grant execute on function public.initiate_trade_payment(uuid,text,text,numeric,text)
to authenticated;

revoke all on function public.confirm_trade_payment(uuid,text)
from public,anon;
grant execute on function public.confirm_trade_payment(uuid,text)
to authenticated;
