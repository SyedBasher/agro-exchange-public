-- Agro-Exchange v1.1: dispatch, transport assignment and proof-of-delivery workflow
-- ready_for_dispatch -> assigned/accepted shipment -> in_transit -> delivered

alter table public.shipments
  add column if not exists status text not null default 'assigned',
  add column if not exists assigned_by_profile_id uuid references public.profiles(id),
  add column if not exists assigned_at timestamptz not null default now(),
  add column if not exists accepted_at timestamptz,
  add column if not exists pickup_due_at timestamptz,
  add column if not exists assignment_notes text,
  add column if not exists recipient_name text,
  add column if not exists delivery_notes text,
  add column if not exists delivered_by_profile_id uuid references public.profiles(id);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='shipments_status_check' and conrelid='public.shipments'::regclass
  ) then
    alter table public.shipments add constraint shipments_status_check
      check (status in ('assigned','accepted','in_transit','delivered','cancelled'));
  end if;
end $$;

create index if not exists shipments_trade_status_idx
  on public.shipments(trade_id,status,created_at desc);
create index if not exists shipments_transporter_status_idx
  on public.shipments(transporter_profile_id,status,created_at desc);

-- Private proof-of-delivery evidence bucket.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('delivery-evidence','delivery-evidence',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

-- Object path convention: <trade_uuid>/<generated-file-name>
drop policy if exists delivery_evidence_insert on storage.objects;
create policy delivery_evidence_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='delivery-evidence'
  and (
    exists (
      select 1 from public.profiles p
      where p.auth_user_id=auth.uid() and p.role='admin'
    )
    or exists (
      select 1
      from public.profiles p
      join public.shipments s on s.transporter_profile_id=p.id
      where p.auth_user_id=auth.uid()
        and p.role='transporter'
        and s.trade_id::text=split_part(storage.objects.name,'/',1)
        and s.status in ('assigned','accepted','in_transit')
    )
  )
);

drop policy if exists delivery_evidence_select on storage.objects;
create policy delivery_evidence_select
on storage.objects for select to authenticated
using (
  bucket_id='delivery-evidence'
  and (
    exists (
      select 1 from public.profiles p
      where p.auth_user_id=auth.uid() and p.role='admin'
    )
    or exists (
      select 1
      from public.profiles p
      join public.shipments s on s.transporter_profile_id=p.id
      where p.auth_user_id=auth.uid()
        and s.trade_id::text=split_part(storage.objects.name,'/',1)
    )
    or exists (
      select 1
      from public.profiles p
      join public.trades t on t.seller_profile_id=p.id
      where p.auth_user_id=auth.uid()
        and t.id::text=split_part(storage.objects.name,'/',1)
    )
    or exists (
      select 1
      from public.profiles p
      join public.buyer_memberships bm on bm.profile_id=p.id
      join public.trades t on t.buyer_organization_id=bm.buyer_organization_id
      where p.auth_user_id=auth.uid()
        and t.id::text=split_part(storage.objects.name,'/',1)
    )
  )
);

create or replace function public.get_dispatch_queue()
returns table(
  trade_id uuid,
  confirmation_reference text,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  origin_district text,
  destination_district text,
  agreed_quantity_kg numeric,
  dispatch_quantity_kg numeric,
  agreed_price_bdt_per_kg numeric,
  delivery_due_at timestamptz,
  qc_record_id uuid,
  certified_scale boolean
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
  if not found or v_profile.role not in ('field_agent','admin') then
    raise exception 'Field-agent or admin access required';
  end if;

  return query
  select t.id,tc.reference,c.code,c.name_en,c.name_bn,lo.district,ld.district,
    t.agreed_quantity_kg,coalesce(q.measured_weight_kg,t.agreed_quantity_kg),
    t.agreed_price_bdt_per_kg,t.delivery_due_at,q.id,q.certified_scale
  from public.trades t
  join public.commodities c on c.id=t.commodity_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join lateral (
    select qr.id,qr.measured_weight_kg,qr.certified_scale
    from public.qc_records qr
    where qr.trade_id=t.id and qr.accepted=true
    order by qr.recorded_at desc limit 1
  ) q on true
  where t.status='ready_for_dispatch'
    and not exists (
      select 1 from public.shipments s
      where s.trade_id=t.id and s.status in ('assigned','accepted','in_transit','delivered')
    )
  order by t.delivery_due_at nulls last,t.created_at;
end;
$$;

create or replace function public.get_available_transporters()
returns table(profile_id uuid,display_name text,verified boolean)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found or v_profile.role not in ('field_agent','admin') then
    raise exception 'Field-agent or admin access required';
  end if;
  return query
    select p.id,p.display_name,p.verified
    from public.profiles p
    where p.role='transporter' and p.verified=true
    order by p.display_name;
end;
$$;

create or replace function public.assign_shipment(
  p_trade_id uuid,
  p_transporter_profile_id uuid,
  p_vehicle_reference text default null,
  p_transport_cost_bdt numeric default null,
  p_pickup_due_at timestamptz default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor public.profiles%rowtype;
  v_transporter public.profiles%rowtype;
  v_trade public.trades%rowtype;
  v_shipment_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_actor from public.profiles where auth_user_id=auth.uid();
  if not found or v_actor.role not in ('field_agent','admin') then raise exception 'Field-agent or admin access required'; end if;

  select * into v_transporter from public.profiles where id=p_transporter_profile_id;
  if not found or v_transporter.role<>'transporter' or v_transporter.verified=false then
    raise exception 'A verified transporter must be selected';
  end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status<>'ready_for_dispatch' then raise exception 'Trade is not ready for dispatch'; end if;
  if p_transport_cost_bdt is not null and p_transport_cost_bdt<0 then raise exception 'Transport cost cannot be negative'; end if;
  if exists(select 1 from public.shipments s where s.trade_id=p_trade_id and s.status in ('assigned','accepted','in_transit','delivered')) then
    raise exception 'This trade already has an active shipment';
  end if;

  insert into public.shipments(
    trade_id,transporter_profile_id,vehicle_reference,pickup_location_id,delivery_location_id,
    transport_cost_bdt,status,assigned_by_profile_id,assigned_at,pickup_due_at,assignment_notes
  ) values (
    v_trade.id,v_transporter.id,nullif(trim(p_vehicle_reference),''),v_trade.origin_location_id,v_trade.destination_location_id,
    p_transport_cost_bdt,'assigned',v_actor.id,now(),p_pickup_due_at,nullif(trim(p_notes),'')
  ) returning id into v_shipment_id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,'ready_for_dispatch',v_actor.id,jsonb_build_object('shipment_id',v_shipment_id,'logistics_event','transporter_assigned','transporter_profile_id',v_transporter.id));

  return v_shipment_id;
end;
$$;

create or replace function public.get_my_shipments()
returns table(
  shipment_id uuid,
  shipment_status text,
  trade_id uuid,
  confirmation_reference text,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  origin_district text,
  destination_district text,
  agreed_quantity_kg numeric,
  measured_quantity_kg numeric,
  vehicle_reference text,
  transport_cost_bdt numeric,
  pickup_due_at timestamptz,
  assigned_at timestamptz,
  accepted_at timestamptz,
  dispatched_at timestamptz,
  delivered_at timestamptz,
  transporter_profile_id uuid,
  transporter_name text,
  recipient_name text
)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;

  return query
  select s.id,s.status,t.id,tc.reference,c.code,c.name_en,c.name_bn,lo.district,ld.district,
    t.agreed_quantity_kg,
    coalesce((select qr.measured_weight_kg from public.qc_records qr where qr.trade_id=t.id and qr.accepted=true order by qr.recorded_at desc limit 1),t.agreed_quantity_kg),
    s.vehicle_reference,s.transport_cost_bdt,s.pickup_due_at,s.assigned_at,s.accepted_at,s.dispatched_at,s.delivered_at,
    s.transporter_profile_id,tp.display_name,s.recipient_name
  from public.shipments s
  join public.trades t on t.id=s.trade_id
  join public.commodities c on c.id=t.commodity_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join public.profiles tp on tp.id=s.transporter_profile_id
  where
    v_profile.role in ('admin','field_agent')
    or s.transporter_profile_id=v_profile.id
    or t.seller_profile_id=v_profile.id
    or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id)
  order by s.created_at desc;
end;
$$;

create or replace function public.accept_shipment(p_shipment_id uuid)
returns table(shipment_id uuid,shipment_status text,trade_id uuid)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype; v_s public.shipments%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_s from public.shipments where id=p_shipment_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  if not (v_s.transporter_profile_id=v_profile.id or v_profile.role='admin') then raise exception 'Only the assigned transporter or admin can accept this shipment'; end if;
  if v_s.status<>'assigned' then raise exception 'Shipment is not awaiting acceptance'; end if;

  update public.shipments set status='accepted',accepted_at=now() where id=v_s.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_s.trade_id,'ready_for_dispatch',v_profile.id,jsonb_build_object('shipment_id',v_s.id,'logistics_event','shipment_accepted'));
  return query select v_s.id,'accepted'::text,v_s.trade_id;
end;
$$;

create or replace function public.dispatch_shipment(p_shipment_id uuid,p_vehicle_reference text default null)
returns table(shipment_id uuid,shipment_status text,trade_id uuid,trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype; v_s public.shipments%rowtype; v_vehicle text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_s from public.shipments where id=p_shipment_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  if not (v_s.transporter_profile_id=v_profile.id or v_profile.role='admin') then raise exception 'Only the assigned transporter or admin can dispatch this shipment'; end if;
  if v_s.status<>'accepted' then raise exception 'Shipment must be accepted before dispatch'; end if;
  v_vehicle:=coalesce(nullif(trim(p_vehicle_reference),''),nullif(trim(v_s.vehicle_reference),''));
  if v_vehicle is null then raise exception 'Vehicle reference is required before dispatch'; end if;

  update public.shipments set status='in_transit',vehicle_reference=v_vehicle,dispatched_at=now() where id=v_s.id;
  update public.trades set status='in_transit',updated_at=now() where id=v_s.trade_id and status='ready_for_dispatch';
  if not found then raise exception 'Trade is not ready for dispatch'; end if;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_s.trade_id,'in_transit',v_profile.id,jsonb_build_object('shipment_id',v_s.id,'vehicle_reference',v_vehicle,'logistics_event','dispatched'));
  return query select v_s.id,'in_transit'::text,v_s.trade_id,'in_transit'::text;
end;
$$;

create or replace function public.complete_shipment_delivery(
  p_shipment_id uuid,
  p_recipient_name text,
  p_notes text default null,
  p_evidence_objects jsonb default '[]'::jsonb
)
returns table(shipment_id uuid,shipment_status text,trade_id uuid,trade_status text,evidence_count integer)
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype; v_s public.shipments%rowtype; v_count integer; v_bad boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid();
  if not found then raise exception 'Profile not found'; end if;
  select * into v_s from public.shipments where id=p_shipment_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  if not (v_s.transporter_profile_id=v_profile.id or v_profile.role='admin') then raise exception 'Only the assigned transporter or admin can complete delivery'; end if;
  if v_s.status<>'in_transit' then raise exception 'Shipment is not in transit'; end if;
  if nullif(trim(p_recipient_name),'') is null then raise exception 'Recipient name is required'; end if;
  if p_evidence_objects is null or jsonb_typeof(p_evidence_objects)<>'array' then raise exception 'Evidence must be a JSON array'; end if;
  v_count:=jsonb_array_length(p_evidence_objects);
  if v_count>4 then raise exception 'No more than four proof-of-delivery images are allowed'; end if;
  select exists(
    select 1 from jsonb_array_elements_text(p_evidence_objects) e(path)
    where split_part(e.path,'/',1)<>v_s.trade_id::text
  ) into v_bad;
  if v_bad then raise exception 'Evidence path does not belong to this trade'; end if;

  update public.shipments set
    status='delivered',delivered_at=now(),recipient_name=trim(p_recipient_name),delivery_notes=nullif(trim(p_notes),''),
    delivered_by_profile_id=v_profile.id,
    proof_of_delivery=jsonb_build_object('recipient_name',trim(p_recipient_name),'notes',nullif(trim(p_notes),''),'evidence_objects',p_evidence_objects,'recorded_at',now(),'recorded_by_profile_id',v_profile.id)
  where id=v_s.id;
  update public.trades set status='delivered',updated_at=now() where id=v_s.trade_id and status='in_transit';
  if not found then raise exception 'Trade is not in transit'; end if;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_s.trade_id,'delivered',v_profile.id,jsonb_build_object('shipment_id',v_s.id,'recipient_name',trim(p_recipient_name),'evidence_count',v_count,'logistics_event','delivered'));
  return query select v_s.id,'delivered'::text,v_s.trade_id,'delivered'::text,v_count;
end;
$$;

revoke all on function public.get_dispatch_queue() from public,anon;
revoke all on function public.get_available_transporters() from public,anon;
revoke all on function public.assign_shipment(uuid,uuid,text,numeric,timestamptz,text) from public,anon;
revoke all on function public.get_my_shipments() from public,anon;
revoke all on function public.accept_shipment(uuid) from public,anon;
revoke all on function public.dispatch_shipment(uuid,text) from public,anon;
revoke all on function public.complete_shipment_delivery(uuid,text,text,jsonb) from public,anon;

grant execute on function public.get_dispatch_queue() to authenticated;
grant execute on function public.get_available_transporters() to authenticated;
grant execute on function public.assign_shipment(uuid,uuid,text,numeric,timestamptz,text) to authenticated;
grant execute on function public.get_my_shipments() to authenticated;
grant execute on function public.accept_shipment(uuid) to authenticated;
grant execute on function public.dispatch_shipment(uuid,text) to authenticated;
grant execute on function public.complete_shipment_delivery(uuid,text,text,jsonb) to authenticated;
