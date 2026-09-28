-- Agro-Exchange v1.2 settlement hardening
-- Prevents duplicate simultaneous payment initiations for the same trade.

create unique index if not exists payments_one_initiated_per_trade_idx
  on public.payments(trade_id)
  where status='initiated';

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
  if exists(select 1 from public.payments where trade_id=p_trade_id and status='initiated') then raise exception 'An initiated payment is already awaiting seller confirmation'; end if;

  if p_amount_bdt is null or p_amount_bdt <= 0 then raise exception 'Payment amount must be greater than zero'; end if;
  v_method := lower(trim(coalesce(p_method,'')));
  if v_method not in ('bank_transfer','mobile_financial_service','cash','other') then raise exception 'Unsupported payment method'; end if;
  if v_method <> 'cash' and nullif(trim(coalesce(p_external_reference,'')),'') is null then raise exception 'Payment reference is required for non-cash payments'; end if;

  select coalesce(sum(amount_bdt),0) into v_confirmed from public.payments where trade_id=p_trade_id and status='confirmed';
  v_remaining := greatest(v_obligation.amount_due_bdt-v_confirmed,0);
  if p_amount_bdt > v_remaining + 0.01 then raise exception 'Payment amount exceeds remaining amount due'; end if;

  insert into public.payments(trade_id,payment_obligation_id,method,external_reference,amount_bdt,status,initiated_at,recorded_by_profile_id,notes,updated_at)
  values(p_trade_id,v_obligation.id,v_method,nullif(trim(coalesce(p_external_reference,'')),''),round(p_amount_bdt,2),'initiated',now(),v_profile.id,nullif(trim(coalesce(p_notes,'')),''),now())
  returning * into v_payment;

  update public.payment_obligations set status='initiated',updated_at=now() where id=v_obligation.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(p_trade_id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_initiated','payment_id',v_payment.id,'method',v_method,'amount_bdt',v_payment.amount_bdt));

  return query select v_payment.id,v_payment.status::text,v_payment.amount_bdt,greatest(v_remaining-v_payment.amount_bdt,0);
end;
$$;
