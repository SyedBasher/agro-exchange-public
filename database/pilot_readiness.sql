-- Agro-Exchange v1.5: pilot readiness and reliability
-- Transparent counterparty history, in-app notifications, exception escalation,
-- and QC cost/time telemetry. Metrics are descriptive; no opaque reliability score.

alter table public.notification_outbox
  add column if not exists read_at timestamptz,
  add column if not exists priority text not null default 'normal',
  add column if not exists available_at timestamptz not null default now(),
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_error text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='notification_outbox_priority_check'
      and conrelid='public.notification_outbox'::regclass
  ) then
    alter table public.notification_outbox
      add constraint notification_outbox_priority_check
      check (priority in ('normal','high','critical'));
  end if;
end $$;

create table if not exists public.notification_preferences (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  sms_opt_in boolean not null default false,
  push_opt_in boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  updated_at timestamptz not null default now()
);

create table if not exists public.operations_escalations (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.trades(id) on delete cascade,
  escalation_level integer not null check (escalation_level between 1 and 3),
  reason text not null,
  status text not null default 'open' check (status in ('open','resolved')),
  created_by_profile_id uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  resolved_by_profile_id uuid references public.profiles(id),
  resolved_at timestamptz,
  resolution_note text
);

create unique index if not exists operations_escalations_one_open_per_trade_idx
  on public.operations_escalations(trade_id) where status='open';
create index if not exists operations_escalations_status_created_idx
  on public.operations_escalations(status,created_at desc);
create index if not exists operations_escalations_created_by_idx
  on public.operations_escalations(created_by_profile_id);
create index if not exists operations_escalations_resolved_by_idx
  on public.operations_escalations(resolved_by_profile_id);

alter table public.qc_records
  add column if not exists inspection_level text,
  add column if not exists inspection_reason text,
  add column if not exists direct_cost_bdt numeric,
  add column if not exists telemetry_recorded_at timestamptz,
  add column if not exists telemetry_recorded_by_profile_id uuid references public.profiles(id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='qc_records_inspection_level_check'
      and conrelid='public.qc_records'::regclass
  ) then
    alter table public.qc_records
      add constraint qc_records_inspection_level_check
      check (inspection_level is null or inspection_level in ('basic','independent','enhanced'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='qc_records_direct_cost_nonnegative'
      and conrelid='public.qc_records'::regclass
  ) then
    alter table public.qc_records
      add constraint qc_records_direct_cost_nonnegative
      check (direct_cost_bdt is null or direct_cost_bdt>=0);
  end if;
end $$;

create index if not exists qc_records_telemetry_recorded_by_idx
  on public.qc_records(telemetry_recorded_by_profile_id);
create index if not exists notification_outbox_unread_idx
  on public.notification_outbox(recipient_profile_id,read_at,created_at desc);

alter table public.notification_preferences enable row level security;
alter table public.operations_escalations enable row level security;

revoke all on public.notification_preferences from anon,authenticated;
revoke all on public.operations_escalations from anon,authenticated;
grant select on public.notification_preferences to authenticated;
grant select on public.operations_escalations to authenticated;

drop policy if exists notification_preferences_own_read on public.notification_preferences;
create policy notification_preferences_own_read
on public.notification_preferences for select to authenticated
using (
  profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
  or exists(select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
);

drop policy if exists operations_escalations_admin_read on public.operations_escalations;
create policy operations_escalations_admin_read
on public.operations_escalations for select to authenticated
using (
  exists(select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
);

create or replace function public.get_my_notifications(p_limit integer default 50)
returns table(
  notification_id uuid,
  trade_id uuid,
  event_type text,
  priority text,
  payload jsonb,
  created_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  update public.notification_outbox n
  set status='sent',sent_at=coalesce(sent_at,now()),attempt_count=attempt_count+1,last_error=null
  where n.recipient_profile_id=v_profile.id
    and n.channel='in_app'
    and n.status='pending'
    and n.available_at<=now();

  return query
  select n.id,n.trade_id,n.event_type,n.priority,n.payload,n.created_at,n.sent_at,n.read_at
  from public.notification_outbox n
  where n.recipient_profile_id=v_profile.id and n.channel='in_app'
    and n.status in ('pending','sent')
  order by n.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),200);
end;
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  update public.notification_outbox
  set read_at=coalesce(read_at,now()),status=case when status='pending' then 'sent' else status end,
      sent_at=case when sent_at is null then now() else sent_at end
  where id=p_notification_id and recipient_profile_id=v_profile.id and channel='in_app';
  return found;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype; v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  update public.notification_outbox
  set read_at=coalesce(read_at,now()),status=case when status='pending' then 'sent' else status end,
      sent_at=case when sent_at is null then now() else sent_at end
  where recipient_profile_id=v_profile.id and channel='in_app' and read_at is null;
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.get_my_notification_preferences()
returns table(sms_opt_in boolean,push_opt_in boolean,quiet_hours_start time,quiet_hours_end time)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  insert into public.notification_preferences(profile_id) values(v_profile.id) on conflict do nothing;
  return query
  select n.sms_opt_in,n.push_opt_in,n.quiet_hours_start,n.quiet_hours_end
  from public.notification_preferences n where n.profile_id=v_profile.id;
end;
$$;

create or replace function public.update_my_notification_preferences(
  p_sms_opt_in boolean default false,
  p_push_opt_in boolean default false,
  p_quiet_hours_start time default null,
  p_quiet_hours_end time default null
)
returns table(sms_opt_in boolean,push_opt_in boolean,quiet_hours_start time,quiet_hours_end time)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  insert into public.notification_preferences(profile_id,sms_opt_in,push_opt_in,quiet_hours_start,quiet_hours_end,updated_at)
  values(v_profile.id,coalesce(p_sms_opt_in,false),coalesce(p_push_opt_in,false),p_quiet_hours_start,p_quiet_hours_end,now())
  on conflict(profile_id) do update set
    sms_opt_in=excluded.sms_opt_in,push_opt_in=excluded.push_opt_in,
    quiet_hours_start=excluded.quiet_hours_start,quiet_hours_end=excluded.quiet_hours_end,updated_at=now();
  return query
  select n.sms_opt_in,n.push_opt_in,n.quiet_hours_start,n.quiet_hours_end
  from public.notification_preferences n where n.profile_id=v_profile.id;
end;
$$;

-- In-app delivery is the active channel in v1.5. SMS/push preferences are stored
-- for future provider integration, but no external delivery is claimed here.
create or replace function public.queue_trade_status_notifications()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_trade public.trades%rowtype;
  v_profile_id uuid;
  v_priority text;
begin
  select * into v_trade from public.trades where id=new.trade_id;
  if not found then return new; end if;
  v_priority:=case when new.status::text in ('disputed','cancelled') then 'high' else 'normal' end;

  insert into public.notification_outbox(recipient_profile_id,trade_id,trade_status_event_id,event_type,priority,payload)
  values(v_trade.seller_profile_id,new.trade_id,new.id,'trade_status_changed',v_priority,
    jsonb_build_object('status',new.status::text,'metadata',coalesce(new.metadata,'{}'::jsonb)))
  on conflict do nothing;

  for v_profile_id in
    select bm.profile_id from public.buyer_memberships bm where bm.buyer_organization_id=v_trade.buyer_organization_id
  loop
    insert into public.notification_outbox(recipient_profile_id,trade_id,trade_status_event_id,event_type,priority,payload)
    values(v_profile_id,new.trade_id,new.id,'trade_status_changed',v_priority,
      jsonb_build_object('status',new.status::text,'metadata',coalesce(new.metadata,'{}'::jsonb)))
    on conflict do nothing;
  end loop;
  return new;
end;
$$;

create or replace function public.record_qc_telemetry(
  p_qc_record_id uuid,
  p_inspection_level text,
  p_direct_cost_bdt numeric,
  p_inspection_reason text default null
)
returns table(qc_record_id uuid,inspection_level text,direct_cost_bdt numeric,inspection_reason text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype; v_q public.qc_records%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator or admin access required'; end if;
  if p_inspection_level not in ('basic','independent','enhanced') then raise exception 'Inspection level must be basic, independent or enhanced'; end if;
  if p_direct_cost_bdt is null or p_direct_cost_bdt<0 then raise exception 'Direct QC cost cannot be negative'; end if;
  select * into v_q from public.qc_records where id=p_qc_record_id for update;
  if not found then raise exception 'QC record not found'; end if;
  update public.qc_records
  set inspection_level=p_inspection_level,direct_cost_bdt=p_direct_cost_bdt,
      inspection_reason=nullif(btrim(coalesce(p_inspection_reason,'')),''),
      telemetry_recorded_at=now(),telemetry_recorded_by_profile_id=v_profile.id
  where id=p_qc_record_id;
  return query select p_qc_record_id,p_inspection_level,p_direct_cost_bdt,nullif(btrim(coalesce(p_inspection_reason,'')),'');
end;
$$;

create or replace function public.get_qc_telemetry_queue()
returns table(
  qc_record_id uuid,trade_id uuid,confirmation_reference text,commodity_code text,
  agreed_value_bdt numeric,accepted boolean,recorded_at timestamptz,
  inspection_level text,direct_cost_bdt numeric,inspection_reason text,
  qc_cycle_hours numeric,telemetry_complete boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator or admin access required'; end if;
  return query
  select q.id,t.id,tc.reference,c.code,
    round(t.agreed_quantity_kg*t.agreed_price_bdt_per_kg,2),q.accepted,q.recorded_at,
    q.inspection_level,q.direct_cost_bdt,q.inspection_reason,
    round((extract(epoch from(q.recorded_at-coalesce((
      select min(e.created_at) from public.trade_status_events e
      where e.trade_id=t.id and e.status='awaiting_qc' and e.created_at<=q.recorded_at
    ),t.confirmed_at)))/3600.0)::numeric,2),
    q.inspection_level is not null and q.direct_cost_bdt is not null
  from public.qc_records q
  join public.trades t on t.id=q.trade_id
  join public.commodities c on c.id=t.commodity_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  order by (q.inspection_level is null or q.direct_cost_bdt is null) desc,q.recorded_at desc
  limit 100;
end;
$$;

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
  if not found or (not v_caller.verified and v_caller.role<>'admin') then raise exception 'Verified account required'; end if;
  select * into v_target from public.profiles where id=p_seller_profile_id and role='farmer';
  if not found then raise exception 'Seller profile not found'; end if;
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

create or replace function public.get_buyer_performance(p_buyer_organization_id uuid)
returns table(
  entity_id uuid,display_name text,total_trades bigint,settled_trades bigint,disputed_trades bigint,cancelled_trades bigint,
  dispute_trade_rate_pct numeric,delivery_receipts bigint,accepted_receipts bigint,receipt_acceptance_rate_pct numeric,
  avg_receipt_confirmation_hours numeric,avg_receipt_to_settlement_hours numeric,sample_band text
)
language plpgsql
security definer
set search_path=public
as $$
declare v_caller public.profiles%rowtype; v_org public.buyer_organizations%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_caller from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or (not v_caller.verified and v_caller.role<>'admin') then raise exception 'Verified account required'; end if;
  select * into v_org from public.buyer_organizations where id=p_buyer_organization_id;
  if not found then raise exception 'Buyer organization not found'; end if;
  return query
  with b as (select t.* from public.trades t where t.buyer_organization_id=v_org.id),
  s as (
    select count(*) total,count(*) filter(where status='settled') settled,count(*) filter(where status='cancelled') cancelled from b
  ),
  d as (select count(distinct td.trade_id) disputed from public.trade_disputes td join b on b.id=td.trade_id),
  r as (
    select count(*) receipts,count(*) filter(where dr.status='accepted') accepted,
      avg(extract(epoch from(dr.confirmed_at-sh.delivered_at))/3600.0) filter(where sh.delivered_at is not null) receipt_hours,
      avg(extract(epoch from(b.settled_at-dr.confirmed_at))/3600.0) filter(where b.settled_at is not null and dr.status='accepted') settle_hours
    from public.delivery_receipts dr join b on b.id=dr.trade_id
    left join public.shipments sh on sh.id=dr.shipment_id
  )
  select v_org.id,v_org.name,s.total,s.settled,d.disputed,s.cancelled,
    case when s.total>0 then round(100*d.disputed::numeric/s.total,1) end,
    r.receipts,r.accepted,case when r.receipts>0 then round(100*r.accepted::numeric/r.receipts,1) end,
    round(coalesce(r.receipt_hours,0)::numeric,1),round(coalesce(r.settle_hours,0)::numeric,1),
    case when s.total<3 then 'limited' when s.total<10 then 'developing' else 'established' end
  from s,d,r;
end;
$$;

create or replace function public.get_my_reliability_snapshot()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype; v_org_id uuid; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  if v_profile.role='farmer' then
    select to_jsonb(x) into v_result from public.get_seller_performance(v_profile.id) x;
    return jsonb_build_object('entity_type','seller','metrics',coalesce(v_result,'{}'::jsonb));
  elsif v_profile.role='buyer' then
    select bm.buyer_organization_id into v_org_id from public.buyer_memberships bm where bm.profile_id=v_profile.id limit 1;
    if v_org_id is null then return jsonb_build_object('entity_type','buyer','metrics','{}'::jsonb); end if;
    select to_jsonb(x) into v_result from public.get_buyer_performance(v_org_id) x;
    return jsonb_build_object('entity_type','buyer','metrics',coalesce(v_result,'{}'::jsonb));
  end if;
  return jsonb_build_object('entity_type',v_profile.role::text,'metrics','{}'::jsonb);
end;
$$;

create or replace function public.get_admin_pilot_readiness()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype; v_result jsonb;
begin
  v_admin:=public.require_admin_profile();
  with q as (
    select q.id,q.accepted,q.direct_cost_bdt,q.recorded_at,t.id trade_id,t.agreed_quantity_kg*t.agreed_price_bdt_per_kg trade_value,
      extract(epoch from(q.recorded_at-coalesce((select min(e.created_at) from public.trade_status_events e where e.trade_id=t.id and e.status='awaiting_qc' and e.created_at<=q.recorded_at),t.confirmed_at)))/3600.0 qc_hours
    from public.qc_records q join public.trades t on t.id=q.trade_id
  ),
  trade_flags as (
    select t.id,coalesce(tc.qc_required,true) qc_required,
      exists(select 1 from public.trade_disputes d where d.trade_id=t.id) has_dispute
    from public.trades t left join public.trade_confirmations tc on tc.trade_id=t.id
  )
  select jsonb_build_object(
    'total_trades',(select count(*) from public.trades),
    'settled_trades',(select count(*) from public.trades where status='settled'),
    'active_disputes',(select count(*) from public.trade_disputes where status in ('open','proposal_pending')),
    'open_escalations',(select count(*) from public.operations_escalations where status='open'),
    'unread_in_app_notifications',(select count(*) from public.notification_outbox where channel='in_app' and read_at is null),
    'qc_records',(select count(*) from q),
    'qc_cost_recorded',(select count(*) from q where direct_cost_bdt is not null),
    'avg_qc_direct_cost_bdt',(select round(avg(direct_cost_bdt),2) from q where direct_cost_bdt is not null),
    'avg_qc_cost_pct_trade_value',(select round(avg(100*direct_cost_bdt/nullif(trade_value,0)),3) from q where direct_cost_bdt is not null),
    'avg_qc_cycle_hours',(select round(avg(qc_hours)::numeric,2) from q),
    'qc_rejection_rate_pct',(select case when count(*)>0 then round(100*count(*) filter(where accepted=false)::numeric/count(*),1) end from q),
    'qc_required_trade_count',(select count(*) from trade_flags where qc_required),
    'qc_bypassed_trade_count',(select count(*) from trade_flags where not qc_required),
    'qc_required_dispute_rate_pct',(select case when count(*)>0 then round(100*count(*) filter(where has_dispute)::numeric/count(*),1) end from trade_flags where qc_required),
    'qc_bypassed_dispute_rate_pct',(select case when count(*)>0 then round(100*count(*) filter(where has_dispute)::numeric/count(*),1) end from trade_flags where not qc_required)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.get_admin_exception_queue_v1_5()
returns table(
  trade_id uuid,confirmation_reference text,commodity_code text,origin_district text,destination_district text,
  trade_status text,age_hours numeric,threshold_hours integer,overdue_hours numeric,qc_required boolean,
  suggested_escalation_level integer,open_escalation_id uuid,open_escalation_level integer
)
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype;
begin
  v_admin:=public.require_admin_profile();
  return query
  select t.id,tc.reference,c.code,lo.district,ld.district,t.status::text,
    round((extract(epoch from(now()-t.updated_at))/3600.0)::numeric,1),r.threshold_hours,
    round(greatest((extract(epoch from(now()-t.updated_at))/3600.0)-r.threshold_hours,0)::numeric,1),
    coalesce(tc.qc_required,true),
    case when extract(epoch from(now()-t.updated_at))/3600.0 >= r.threshold_hours*4 then 3
         when extract(epoch from(now()-t.updated_at))/3600.0 >= r.threshold_hours*2 then 2 else 1 end,
    oe.id,oe.escalation_level
  from public.trades t
  join public.operations_sla_rules r on r.trade_status=t.status and r.active
  join public.commodities c on c.id=t.commodity_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join public.operations_escalations oe on oe.trade_id=t.id and oe.status='open'
  where t.status not in ('settled','cancelled')
    and extract(epoch from(now()-t.updated_at))/3600.0 > r.threshold_hours
  order by suggested_escalation_level desc,overdue_hours desc;
end;
$$;

create or replace function public.admin_raise_trade_escalation(p_trade_id uuid,p_level integer,p_reason text)
returns table(escalation_id uuid,escalation_level integer,status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype; v_trade public.trades%rowtype; v_id uuid; v_profile_id uuid; v_priority text;
begin
  v_admin:=public.require_admin_profile();
  if p_level not between 1 and 3 then raise exception 'Escalation level must be 1, 2 or 3'; end if;
  if nullif(btrim(coalesce(p_reason,'')),'') is null then raise exception 'Escalation reason is required'; end if;
  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status in ('settled','cancelled') then raise exception 'Terminal trade cannot be escalated'; end if;

  insert into public.operations_escalations(trade_id,escalation_level,reason,created_by_profile_id)
  values(v_trade.id,p_level,btrim(p_reason),v_admin.id)
  on conflict (trade_id) where status='open' do update
    set escalation_level=excluded.escalation_level,reason=excluded.reason,created_by_profile_id=v_admin.id,created_at=now()
  returning id into v_id;

  v_priority:=case when p_level=3 then 'critical' else 'high' end;
  insert into public.notification_outbox(recipient_profile_id,trade_id,event_type,priority,payload)
  values(v_trade.seller_profile_id,v_trade.id,'operations_escalation',v_priority,jsonb_build_object('level',p_level,'reason',btrim(p_reason))) ;
  for v_profile_id in select bm.profile_id from public.buyer_memberships bm where bm.buyer_organization_id=v_trade.buyer_organization_id loop
    insert into public.notification_outbox(recipient_profile_id,trade_id,event_type,priority,payload)
    values(v_profile_id,v_trade.id,'operations_escalation',v_priority,jsonb_build_object('level',p_level,'reason',btrim(p_reason)));
  end loop;
  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'trade_escalation_raised','trade',v_trade.id,jsonb_build_object('level',p_level,'reason',btrim(p_reason),'escalation_id',v_id));
  return query select v_id,p_level,'open'::text;
end;
$$;

create or replace function public.admin_resolve_trade_escalation(p_escalation_id uuid,p_resolution_note text)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype; v_e public.operations_escalations%rowtype;
begin
  v_admin:=public.require_admin_profile();
  select * into v_e from public.operations_escalations where id=p_escalation_id for update;
  if not found then raise exception 'Escalation not found'; end if;
  if v_e.status='resolved' then return true; end if;
  update public.operations_escalations set status='resolved',resolved_by_profile_id=v_admin.id,resolved_at=now(),resolution_note=nullif(btrim(coalesce(p_resolution_note,'')),'') where id=v_e.id;
  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'trade_escalation_resolved','trade',v_e.trade_id,jsonb_build_object('escalation_id',v_e.id,'resolution_note',nullif(btrim(coalesce(p_resolution_note,'')),'')));
  return true;
end;
$$;

revoke all on function public.get_my_notifications(integer) from public,anon;
revoke all on function public.mark_notification_read(uuid) from public,anon;
revoke all on function public.mark_all_notifications_read() from public,anon;
revoke all on function public.get_my_notification_preferences() from public,anon;
revoke all on function public.update_my_notification_preferences(boolean,boolean,time,time) from public,anon;
revoke all on function public.record_qc_telemetry(uuid,text,numeric,text) from public,anon;
revoke all on function public.get_qc_telemetry_queue() from public,anon;
revoke all on function public.get_seller_performance(uuid) from public,anon;
revoke all on function public.get_buyer_performance(uuid) from public,anon;
revoke all on function public.get_my_reliability_snapshot() from public,anon;
revoke all on function public.get_admin_pilot_readiness() from public,anon;
revoke all on function public.get_admin_exception_queue_v1_5() from public,anon;
revoke all on function public.admin_raise_trade_escalation(uuid,integer,text) from public,anon;
revoke all on function public.admin_resolve_trade_escalation(uuid,text) from public,anon;

grant execute on function public.get_my_notifications(integer) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
grant execute on function public.get_my_notification_preferences() to authenticated;
grant execute on function public.update_my_notification_preferences(boolean,boolean,time,time) to authenticated;
grant execute on function public.record_qc_telemetry(uuid,text,numeric,text) to authenticated;
grant execute on function public.get_qc_telemetry_queue() to authenticated;
grant execute on function public.get_seller_performance(uuid) to authenticated;
grant execute on function public.get_buyer_performance(uuid) to authenticated;
grant execute on function public.get_my_reliability_snapshot() to authenticated;
grant execute on function public.get_admin_pilot_readiness() to authenticated;
grant execute on function public.get_admin_exception_queue_v1_5() to authenticated;
grant execute on function public.admin_raise_trade_escalation(uuid,integer,text) to authenticated;
grant execute on function public.admin_resolve_trade_escalation(uuid,text) to authenticated;
