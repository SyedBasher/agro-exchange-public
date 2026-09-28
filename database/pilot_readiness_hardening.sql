-- Agro-Exchange v1.5 hardening
-- Let a participant inspect their own seller history before verification while
-- keeping other counterparties' performance history restricted to verified users.

create or replace function public.get_seller_performance(p_seller_profile_id uuid)
returns table(
  entity_id uuid,display_name text,total_trades bigint,settled_trades bigint,disputed_trades bigint,cancelled_trades bigint,
  dispute_trade_rate_pct numeric,qc_checks bigint,qc_rejections bigint,qc_rejection_rate_pct numeric,
  delivered_shipments bigint,on_time_deliveries bigint,on_time_delivery_rate_pct numeric,avg_delivery_delay_hours numeric,sample_band text
)
language plpgsql
security definer
set search_path=public
as $$
declare v_caller public.profiles%rowtype; v_target public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_caller from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  select * into v_target from public.profiles where id=p_seller_profile_id and role='farmer';
  if not found then raise exception 'Seller profile not found'; end if;

  -- A user may always inspect their own history. Viewing another seller's
  -- history requires a verified account (admin remains allowed explicitly).
  if v_caller.id<>v_target.id and not v_caller.verified and v_caller.role<>'admin' then
    raise exception 'Verified account required to view another counterparty';
  end if;

  return query
  with b as (select t.* from public.trades t where t.seller_profile_id=v_target.id),
  s as (
    select count(*) total,
      count(*) filter(where status='settled') settled,
      count(*) filter(where status='cancelled') cancelled
    from b
  ),
  d as (select count(distinct td.trade_id) disputed from public.trade_disputes td join b on b.id=td.trade_id),
  q as (
    select count(*) checks,count(*) filter(where qr.accepted=false) rejected
    from public.qc_records qr join b on b.id=qr.trade_id
  ),
  sh as (
    select count(*) filter(where x.delivered_at is not null) delivered,
      count(*) filter(where x.delivered_at is not null and b.delivery_due_at is not null and x.delivered_at<=b.delivery_due_at) ontime,
      avg(greatest(extract(epoch from(x.delivered_at-b.delivery_due_at))/3600.0,0)) filter(where x.delivered_at is not null and b.delivery_due_at is not null) avg_delay
    from public.shipments x join b on b.id=x.trade_id
  )
  select v_target.id,v_target.display_name,s.total,s.settled,d.disputed,s.cancelled,
    case when s.total>0 then round(100*d.disputed::numeric/s.total,1) end,
    q.checks,q.rejected,case when q.checks>0 then round(100*q.rejected::numeric/q.checks,1) end,
    sh.delivered,sh.ontime,case when sh.delivered>0 then round(100*sh.ontime::numeric/sh.delivered,1) end,
    round(coalesce(sh.avg_delay,0)::numeric,1),
    case when s.total<3 then 'limited' when s.total<10 then 'developing' else 'established' end
  from s,d,q,sh;
end;
$$;

revoke all on function public.get_seller_performance(uuid) from public,anon;
grant execute on function public.get_seller_performance(uuid) to authenticated;
