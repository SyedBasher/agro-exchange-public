-- Agro-Exchange v1.4: admin and operations console backend
-- Includes role/organization approvals, exception monitoring, audit logging,
-- notification outbox groundwork, and a no-QC route to dispatch readiness.

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_profile_id uuid not null references public.profiles(id),
  action text not null,
  target_type text not null,
  target_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx on public.admin_audit_log(created_at desc);
create index if not exists admin_audit_log_actor_idx on public.admin_audit_log(actor_profile_id,created_at desc);

create table if not exists public.operations_sla_rules (
  trade_status public.trade_status primary key,
  threshold_hours integer not null check (threshold_hours > 0),
  active boolean not null default true,
  note text,
  updated_by_profile_id uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

insert into public.operations_sla_rules(trade_status,threshold_hours,note)
values
  ('confirmed',24,'Pilot threshold. Confirmed trades should either enter QC or bypass QC to dispatch readiness.'),
  ('awaiting_qc',24,'Pilot threshold for completing required QC.'),
  ('ready_for_dispatch',12,'Pilot threshold for transport assignment and pickup preparation.'),
  ('in_transit',24,'Pilot threshold for exception review; route-specific rules should replace this later.'),
  ('delivered',24,'Pilot threshold for buyer receipt confirmation.'),
  ('disputed',48,'Pilot threshold for a resolution proposal or review.')
on conflict (trade_status) do nothing;

create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  trade_id uuid references public.trades(id) on delete cascade,
  trade_status_event_id bigint references public.trade_status_events(id) on delete cascade,
  event_type text not null,
  channel text not null default 'in_app' check (channel in ('in_app','sms','email','push')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','sent','failed','suppressed')),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(recipient_profile_id,trade_status_event_id,channel)
);

create index if not exists notification_outbox_status_idx on public.notification_outbox(status,created_at);
create index if not exists notification_outbox_recipient_idx on public.notification_outbox(recipient_profile_id,created_at desc);
create index if not exists notification_outbox_trade_idx on public.notification_outbox(trade_id,created_at desc);

alter table public.admin_audit_log enable row level security;
alter table public.operations_sla_rules enable row level security;
alter table public.notification_outbox enable row level security;

revoke all on public.admin_audit_log from anon,authenticated;
revoke all on public.operations_sla_rules from anon,authenticated;
revoke all on public.notification_outbox from anon,authenticated;

grant select on public.operations_sla_rules to authenticated;
grant select on public.notification_outbox to authenticated;

drop policy if exists admin_audit_log_admin_read on public.admin_audit_log;
create policy admin_audit_log_admin_read
on public.admin_audit_log for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.auth_user_id=(select auth.uid()) and p.role='admin'
  )
);

drop policy if exists operations_sla_admin_read on public.operations_sla_rules;
create policy operations_sla_admin_read
on public.operations_sla_rules for select to authenticated
using (
  exists (
    select 1 from public.profiles p
    where p.auth_user_id=(select auth.uid()) and p.role='admin'
  )
);

drop policy if exists notification_outbox_participant_read on public.notification_outbox;
create policy notification_outbox_participant_read
on public.notification_outbox for select to authenticated
using (
  recipient_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
  or exists (
    select 1 from public.profiles p
    where p.auth_user_id=(select auth.uid()) and p.role='admin'
  )
);

create or replace function public.require_admin_profile()
returns public.profiles
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role<>'admin' then raise exception 'Admin access required'; end if;
  return v_profile;
end;
$$;

revoke all on function public.require_admin_profile() from public,anon,authenticated;

create or replace function public.get_admin_dashboard()
returns table(
  unverified_profiles bigint,
  unverified_buyer_organizations bigint,
  active_trades bigint,
  stalled_trades bigint,
  active_disputes bigint,
  pending_notifications bigint,
  qc_required_active bigint,
  qc_bypassed_active bigint
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_admin public.profiles%rowtype;
begin
  v_admin:=public.require_admin_profile();
  return query
  select
    (select count(*) from public.profiles p where not p.verified),
    (select count(*) from public.buyer_organizations o where not o.verified),
    (select count(*) from public.trades t where t.status not in ('settled','cancelled')),
    (select count(*)
      from public.trades t
      join public.operations_sla_rules r on r.trade_status=t.status and r.active
      where t.status not in ('settled','cancelled')
        and extract(epoch from (now()-t.updated_at))/3600.0 > r.threshold_hours),
    (select count(*) from public.trade_disputes d where d.status in ('open','proposal_pending')),
    (select count(*) from public.notification_outbox n where n.status='pending'),
    (select count(*)
      from public.trades t
      join public.trade_confirmations tc on tc.trade_id=t.id
      where t.status not in ('settled','cancelled') and tc.qc_required=true),
    (select count(*)
      from public.trades t
      join public.trade_confirmations tc on tc.trade_id=t.id
      where t.status not in ('settled','cancelled') and tc.qc_required=false);
end;
$$;

create or replace function public.get_admin_profiles()
returns table(
  profile_id uuid,
  display_name text,
  phone text,
  role text,
  verified boolean,
  preferred_language text,
  buyer_organization_id uuid,
  buyer_organization_name text,
  buyer_organization_verified boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype;
begin
  v_admin:=public.require_admin_profile();
  return query
  select p.id,p.display_name,p.phone,p.role::text,p.verified,p.preferred_language,
         bo.id,bo.name,bo.verified,p.created_at
  from public.profiles p
  left join public.buyer_memberships bm on bm.profile_id=p.id
  left join public.buyer_organizations bo on bo.id=bm.buyer_organization_id
  order by p.verified asc,p.created_at desc;
end;
$$;

create or replace function public.get_admin_buyer_organizations()
returns table(
  buyer_organization_id uuid,
  name text,
  buyer_type text,
  verified boolean,
  district text,
  member_count bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype;
begin
  v_admin:=public.require_admin_profile();
  return query
  select bo.id,bo.name,bo.buyer_type,bo.verified,l.district,count(bm.profile_id),bo.created_at
  from public.buyer_organizations bo
  left join public.locations l on l.id=bo.location_id
  left join public.buyer_memberships bm on bm.buyer_organization_id=bo.id
  group by bo.id,bo.name,bo.buyer_type,bo.verified,l.district,bo.created_at
  order by bo.verified asc,bo.created_at desc;
end;
$$;

create or replace function public.admin_update_profile_access(
  p_profile_id uuid,
  p_verified boolean,
  p_role text,
  p_buyer_organization_id uuid default null,
  p_note text default null
)
returns table(profile_id uuid, role text, verified boolean, buyer_organization_id uuid)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_admin public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_role public.user_role;
  v_org public.buyer_organizations%rowtype;
begin
  v_admin:=public.require_admin_profile();
  if p_profile_id=v_admin.id then raise exception 'An admin cannot change their own access through this workflow'; end if;
  select * into v_target from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'Profile not found'; end if;
  begin
    v_role:=p_role::public.user_role;
  exception when invalid_text_representation then
    raise exception 'Invalid role';
  end;

  if v_role='buyer' then
    if p_buyer_organization_id is null then raise exception 'Buyer organization is required for buyer role'; end if;
    select * into v_org from public.buyer_organizations where id=p_buyer_organization_id;
    if not found then raise exception 'Buyer organization not found'; end if;
    if coalesce(p_verified,false) and not v_org.verified then raise exception 'Buyer organization must be verified before approving a buyer'; end if;
  end if;

  update public.profiles
  set role=v_role,verified=coalesce(p_verified,false),updated_at=now()
  where id=p_profile_id;

  if v_role='buyer' and p_buyer_organization_id is not null then
    insert into public.buyer_memberships(buyer_organization_id,profile_id)
    values(p_buyer_organization_id,p_profile_id)
    on conflict do nothing;
  end if;

  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'profile_access_updated','profile',p_profile_id,
    jsonb_build_object('old_role',v_target.role::text,'new_role',v_role::text,'old_verified',v_target.verified,
      'new_verified',coalesce(p_verified,false),'buyer_organization_id',p_buyer_organization_id,'note',nullif(trim(coalesce(p_note,'')),'')));

  return query select p_profile_id,v_role::text,coalesce(p_verified,false),p_buyer_organization_id;
end;
$$;

create or replace function public.admin_update_buyer_organization(
  p_buyer_organization_id uuid,
  p_verified boolean,
  p_note text default null
)
returns table(buyer_organization_id uuid, verified boolean)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_admin public.profiles%rowtype;
  v_org public.buyer_organizations%rowtype;
begin
  v_admin:=public.require_admin_profile();
  select * into v_org from public.buyer_organizations where id=p_buyer_organization_id for update;
  if not found then raise exception 'Buyer organization not found'; end if;
  update public.buyer_organizations set verified=coalesce(p_verified,false) where id=p_buyer_organization_id;
  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'buyer_organization_verification_updated','buyer_organization',p_buyer_organization_id,
    jsonb_build_object('old_verified',v_org.verified,'new_verified',coalesce(p_verified,false),'note',nullif(trim(coalesce(p_note,'')),'')));
  return query select p_buyer_organization_id,coalesce(p_verified,false);
end;
$$;

create or replace function public.get_admin_exception_queue()
returns table(
  trade_id uuid,
  confirmation_reference text,
  commodity_code text,
  origin_district text,
  destination_district text,
  trade_status text,
  age_hours numeric,
  threshold_hours integer,
  overdue_hours numeric,
  qc_required boolean,
  active_dispute_id uuid
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
    round((extract(epoch from (now()-t.updated_at))/3600.0)::numeric,1),r.threshold_hours,
    round(greatest((extract(epoch from (now()-t.updated_at))/3600.0)-r.threshold_hours,0)::numeric,1),
    coalesce(tc.qc_required,true),d.id
  from public.trades t
  join public.operations_sla_rules r on r.trade_status=t.status and r.active
  join public.commodities c on c.id=t.commodity_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join public.trade_disputes d on d.trade_id=t.id and d.status in ('open','proposal_pending')
  where t.status not in ('settled','cancelled')
    and extract(epoch from (now()-t.updated_at))/3600.0 > r.threshold_hours
  order by overdue_hours desc,t.updated_at asc;
end;
$$;

create or replace function public.get_admin_audit_log(p_limit integer default 50)
returns table(
  audit_id uuid,
  actor_name text,
  action text,
  target_type text,
  target_id uuid,
  details jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype;
begin
  v_admin:=public.require_admin_profile();
  return query
  select a.id,p.display_name,a.action,a.target_type,a.target_id,a.details,a.created_at
  from public.admin_audit_log a
  join public.profiles p on p.id=a.actor_profile_id
  order by a.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),200);
end;
$$;

create or replace function public.admin_update_sla_rule(
  p_trade_status text,
  p_threshold_hours integer,
  p_active boolean default true,
  p_note text default null
)
returns table(trade_status text, threshold_hours integer, active boolean)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_admin public.profiles%rowtype;
  v_status public.trade_status;
begin
  v_admin:=public.require_admin_profile();
  if p_threshold_hours is null or p_threshold_hours<=0 then raise exception 'Threshold hours must be greater than zero'; end if;
  begin v_status:=p_trade_status::public.trade_status;
  exception when invalid_text_representation then raise exception 'Invalid trade status'; end;
  if v_status in ('settled','cancelled') then raise exception 'SLA monitoring is not used for terminal trade states'; end if;

  insert into public.operations_sla_rules(trade_status,threshold_hours,active,note,updated_by_profile_id,updated_at)
  values(v_status,p_threshold_hours,coalesce(p_active,true),nullif(trim(coalesce(p_note,'')),''),v_admin.id,now())
  on conflict (trade_status) do update
    set threshold_hours=excluded.threshold_hours,active=excluded.active,note=excluded.note,
        updated_by_profile_id=v_admin.id,updated_at=now();

  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'operations_sla_updated','trade_status',null,
    jsonb_build_object('trade_status',v_status::text,'threshold_hours',p_threshold_hours,'active',coalesce(p_active,true),'note',nullif(trim(coalesce(p_note,'')),'')));

  return query select v_status::text,p_threshold_hours,coalesce(p_active,true);
end;
$$;

-- Queue in-app events whenever a trade status event is written. External delivery
-- channels can consume this outbox later; no SMS/email/push is sent in v1.4.
create or replace function public.queue_trade_status_notifications()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_trade public.trades%rowtype;
  v_profile_id uuid;
begin
  select * into v_trade from public.trades where id=new.trade_id;
  if not found then return new; end if;

  insert into public.notification_outbox(recipient_profile_id,trade_id,trade_status_event_id,event_type,payload)
  values(v_trade.seller_profile_id,new.trade_id,new.id,'trade_status_changed',
    jsonb_build_object('status',new.status::text,'metadata',coalesce(new.metadata,'{}'::jsonb)))
  on conflict do nothing;

  for v_profile_id in
    select bm.profile_id from public.buyer_memberships bm where bm.buyer_organization_id=v_trade.buyer_organization_id
  loop
    insert into public.notification_outbox(recipient_profile_id,trade_id,trade_status_event_id,event_type,payload)
    values(v_profile_id,new.trade_id,new.id,'trade_status_changed',
      jsonb_build_object('status',new.status::text,'metadata',coalesce(new.metadata,'{}'::jsonb)))
    on conflict do nothing;
  end loop;

  return new;
end;
$$;

drop trigger if exists trade_status_event_notification_outbox on public.trade_status_events;
create trigger trade_status_event_notification_outbox
after insert on public.trade_status_events
for each row execute function public.queue_trade_status_notifications();

-- Selective QC cost-control path. When both parties confirm a trade with
-- qc_required=false, the normal confirmation event is still written, then this
-- trigger moves the trade directly to ready_for_dispatch. This keeps QC optional
-- without leaving non-QC trades stuck in `confirmed`.
create or replace function public.route_trade_when_qc_not_required()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.status='confirmed'
     and coalesce((new.metadata->>'qc_required')::boolean,true)=false then
    update public.trades
      set status='ready_for_dispatch',updated_at=now()
      where id=new.trade_id and status='confirmed';
    if found then
      insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(new.trade_id,'ready_for_dispatch',new.changed_by_profile_id,
        jsonb_build_object('workflow','selective-qc-v1.4','qc_required',false,'reason','QC waived by agreed trade terms'));
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists route_no_qc_after_confirmation_event on public.trade_status_events;
create trigger route_no_qc_after_confirmation_event
after insert on public.trade_status_events
for each row when (new.status='confirmed')
execute function public.route_trade_when_qc_not_required();

revoke all on function public.get_admin_dashboard() from public,anon;
revoke all on function public.get_admin_profiles() from public,anon;
revoke all on function public.get_admin_buyer_organizations() from public,anon;
revoke all on function public.admin_update_profile_access(uuid,boolean,text,uuid,text) from public,anon;
revoke all on function public.admin_update_buyer_organization(uuid,boolean,text) from public,anon;
revoke all on function public.get_admin_exception_queue() from public,anon;
revoke all on function public.get_admin_audit_log(integer) from public,anon;
revoke all on function public.admin_update_sla_rule(text,integer,boolean,text) from public,anon;
revoke all on function public.queue_trade_status_notifications() from public,anon,authenticated;
revoke all on function public.route_trade_when_qc_not_required() from public,anon,authenticated;

grant execute on function public.get_admin_dashboard() to authenticated;
grant execute on function public.get_admin_profiles() to authenticated;
grant execute on function public.get_admin_buyer_organizations() to authenticated;
grant execute on function public.admin_update_profile_access(uuid,boolean,text,uuid,text) to authenticated;
grant execute on function public.admin_update_buyer_organization(uuid,boolean,text) to authenticated;
grant execute on function public.get_admin_exception_queue() to authenticated;
grant execute on function public.get_admin_audit_log(integer) to authenticated;
grant execute on function public.admin_update_sla_rule(text,integer,boolean,text) to authenticated;
