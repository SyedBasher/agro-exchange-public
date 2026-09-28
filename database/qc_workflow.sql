-- Agro-Exchange v1.0: QC, weighing and evidence workflow
-- A QC operator records measured weight/grade and evidence before dispatch.

alter table public.qc_records
  add column if not exists certified_scale boolean not null default false,
  add column if not exists scale_reference text,
  add column if not exists weighing_method text not null default 'digital_scale',
  add column if not exists evidence_objects jsonb not null default '[]'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='qc_records_evidence_objects_array'
      and conrelid='public.qc_records'::regclass
  ) then
    alter table public.qc_records
      add constraint qc_records_evidence_objects_array
      check (jsonb_typeof(evidence_objects)='array');
  end if;
end $$;

-- Private photo/evidence bucket. Object paths are trade_id/random-file-name.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'qc-evidence','qc-evidence',false,5242880,
  array['image/jpeg','image/png','image/webp']
)
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists qc_evidence_insert_operator on storage.objects;
create policy qc_evidence_insert_operator
on storage.objects for insert
to authenticated
with check (
  bucket_id='qc-evidence'
  and exists (
    select 1 from public.profiles p
    where p.auth_user_id=auth.uid()
      and p.role in ('qc_operator','admin')
  )
);

drop policy if exists qc_evidence_select_participant on storage.objects;
create policy qc_evidence_select_participant
on storage.objects for select
to authenticated
using (
  bucket_id='qc-evidence'
  and (
    exists (
      select 1 from public.profiles p
      where p.auth_user_id=auth.uid()
        and p.role in ('qc_operator','admin')
    )
    or exists (
      select 1
      from public.trades t
      where t.id::text=split_part(storage.objects.name,'/',1)
        and (
          t.seller_profile_id=(select p.id from public.profiles p where p.auth_user_id=auth.uid() limit 1)
          or exists (
            select 1
            from public.buyer_memberships bm
            join public.profiles p on p.id=bm.profile_id
            where p.auth_user_id=auth.uid()
              and bm.buyer_organization_id=t.buyer_organization_id
          )
        )
    )
  )
);

drop policy if exists qc_evidence_delete_admin on storage.objects;
create policy qc_evidence_delete_admin
on storage.objects for delete
to authenticated
using (
  bucket_id='qc-evidence'
  and exists (
    select 1 from public.profiles p
    where p.auth_user_id=auth.uid() and p.role='admin'
  )
);

create or replace function public.get_qc_queue()
returns table(
  trade_id uuid,
  confirmation_reference text,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  grade_code text,
  origin_district text,
  destination_district text,
  agreed_quantity_kg numeric,
  agreed_price_bdt_per_kg numeric,
  delivery_due_at timestamptz,
  trade_status text,
  qc_required boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_role not in ('qc_operator','admin') then raise exception 'QC operator access required'; end if;

  return query
  select
    t.id,
    tc.reference,
    c.code,
    c.name_en,
    c.name_bn,
    g.code,
    lo.district,
    ld.district,
    t.agreed_quantity_kg,
    t.agreed_price_bdt_per_kg,
    t.delivery_due_at,
    t.status::text,
    coalesce(tc.qc_required,true)
  from public.trades t
  join public.commodities c on c.id=t.commodity_id
  left join public.commodity_grades g on g.id=t.grade_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  where t.status in ('confirmed','awaiting_qc')
    and coalesce(tc.qc_required,true)=true
  order by t.delivery_due_at nulls last,t.created_at;
end;
$$;

create or replace function public.begin_trade_qc(p_trade_id uuid)
returns table(trade_id uuid, trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trades%rowtype;
  v_required boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator access required'; end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  select coalesce(tc.qc_required,true) into v_required
  from public.trade_confirmations tc where tc.trade_id=v_trade.id limit 1;
  v_required:=coalesce(v_required,true);
  if not v_required then raise exception 'QC is not required for this trade'; end if;

  if v_trade.status='confirmed' then
    update public.trades set status='awaiting_qc',updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'awaiting_qc',v_profile.id,jsonb_build_object('workflow','qc-v1.0'));
  elsif v_trade.status<>'awaiting_qc' then
    raise exception 'Trade is not available for QC in its current state: %',v_trade.status;
  end if;

  return query select v_trade.id,(select t.status::text from public.trades t where t.id=v_trade.id);
end;
$$;

create or replace function public.record_trade_qc(
  p_trade_id uuid,
  p_measured_weight_kg numeric,
  p_accepted_grade_code text,
  p_accepted boolean,
  p_certified_scale boolean default false,
  p_scale_reference text default null,
  p_weighing_method text default 'digital_scale',
  p_notes text default null,
  p_evidence_objects jsonb default '[]'::jsonb
)
returns table(
  qc_record_id uuid,
  trade_id uuid,
  trade_status text,
  weight_variance_pct numeric,
  evidence_count integer
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trades%rowtype;
  v_grade_id uuid;
  v_record_id uuid;
  v_new_status public.trade_status;
  v_variance numeric;
  v_evidence jsonb:=coalesce(p_evidence_objects,'[]'::jsonb);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator access required'; end if;

  if p_measured_weight_kg is null or p_measured_weight_kg<=0 then raise exception 'Measured weight must be greater than zero'; end if;
  if p_accepted is null then raise exception 'QC acceptance decision is required'; end if;
  if jsonb_typeof(v_evidence)<>'array' then raise exception 'Evidence must be a JSON array'; end if;
  if jsonb_array_length(v_evidence)>4 then raise exception 'A maximum of four QC evidence images is allowed'; end if;
  if coalesce(p_certified_scale,false) and nullif(btrim(coalesce(p_scale_reference,'')),'') is null then
    raise exception 'Scale reference is required when certified scale is selected';
  end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status not in ('confirmed','awaiting_qc') then raise exception 'Trade is not available for QC in its current state: %',v_trade.status; end if;

  if v_trade.status='confirmed' then
    update public.trades set status='awaiting_qc',updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
      values(v_trade.id,'awaiting_qc',v_profile.id,jsonb_build_object('workflow','qc-v1.0','auto_started',true));
  end if;

  v_grade_id:=v_trade.grade_id;
  if nullif(btrim(coalesce(p_accepted_grade_code,'')),'') is not null then
    select cg.id into v_grade_id
    from public.commodity_grades cg
    where cg.commodity_id=v_trade.commodity_id and upper(cg.code)=upper(p_accepted_grade_code)
    limit 1;
    if v_grade_id is null then raise exception 'Accepted grade not found for this commodity'; end if;
  end if;

  insert into public.qc_records(
    trade_id,operator_profile_id,location_id,measured_weight_kg,accepted_grade_id,accepted,
    notes,photo_urls,certified_scale,scale_reference,weighing_method,evidence_objects
  ) values (
    v_trade.id,v_profile.id,v_trade.origin_location_id,p_measured_weight_kg,v_grade_id,p_accepted,
    nullif(btrim(coalesce(p_notes,'')),''),v_evidence,coalesce(p_certified_scale,false),
    nullif(btrim(coalesce(p_scale_reference,'')),''),coalesce(nullif(btrim(p_weighing_method),''),'digital_scale'),v_evidence
  ) returning id into v_record_id;

  v_variance:=round(100*(p_measured_weight_kg-v_trade.agreed_quantity_kg)/nullif(v_trade.agreed_quantity_kg,0),2);
  v_new_status:=case when p_accepted then 'ready_for_dispatch'::public.trade_status else 'disputed'::public.trade_status end;

  update public.trades set status=v_new_status,updated_at=now() where id=v_trade.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(
      v_trade.id,v_new_status,v_profile.id,
      jsonb_build_object(
        'workflow','qc-v1.0',
        'qc_record_id',v_record_id,
        'accepted',p_accepted,
        'measured_weight_kg',p_measured_weight_kg,
        'weight_variance_pct',v_variance,
        'certified_scale',coalesce(p_certified_scale,false),
        'scale_reference',nullif(btrim(coalesce(p_scale_reference,'')),''),
        'evidence_count',jsonb_array_length(v_evidence)
      )
    );

  return query select v_record_id,v_trade.id,v_new_status::text,v_variance,jsonb_array_length(v_evidence);
end;
$$;

create or replace function public.get_trade_qc_records(p_trade_id uuid)
returns table(
  qc_record_id uuid,
  measured_weight_kg numeric,
  accepted_grade_code text,
  accepted boolean,
  certified_scale boolean,
  scale_reference text,
  weighing_method text,
  notes text,
  evidence_objects jsonb,
  operator_name text,
  recorded_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_trade public.trades%rowtype;
  v_allowed boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  select * into v_trade from public.trades where id=p_trade_id;
  if not found then raise exception 'Trade not found'; end if;

  v_allowed:=v_profile.role in ('qc_operator','admin') or v_trade.seller_profile_id=v_profile.id or exists(
    select 1 from public.buyer_memberships bm
    where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id
  );
  if not v_allowed then raise exception 'You are not a participant in this trade'; end if;

  return query
  select q.id,q.measured_weight_kg,g.code,q.accepted,q.certified_scale,q.scale_reference,q.weighing_method,
    q.notes,q.evidence_objects,p.display_name,q.recorded_at
  from public.qc_records q
  left join public.commodity_grades g on g.id=q.accepted_grade_id
  join public.profiles p on p.id=q.operator_profile_id
  where q.trade_id=p_trade_id
  order by q.recorded_at desc;
end;
$$;

revoke all on function public.get_qc_queue() from public,anon;
revoke all on function public.begin_trade_qc(uuid) from public,anon;
revoke all on function public.record_trade_qc(uuid,numeric,text,boolean,boolean,text,text,text,jsonb) from public,anon;
revoke all on function public.get_trade_qc_records(uuid) from public,anon;
grant execute on function public.get_qc_queue() to authenticated;
grant execute on function public.begin_trade_qc(uuid) to authenticated;
grant execute on function public.record_trade_qc(uuid,numeric,text,boolean,boolean,text,text,text,jsonb) to authenticated;
grant execute on function public.get_trade_qc_records(uuid) to authenticated;
