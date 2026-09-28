-- Agro-Exchange v1.9 follow-up — operational queues and FK coverage.

create index if not exists shipments_cancelled_by_idx
  on public.shipments(cancelled_by_profile_id)
  where cancelled_by_profile_id is not null;

create index if not exists trade_confirmations_declined_by_idx
  on public.trade_confirmations(declined_by_profile_id)
  where declined_by_profile_id is not null;

create index if not exists trades_qc_assigned_by_idx
  on public.trades(qc_assigned_by_profile_id)
  where qc_assigned_by_profile_id is not null;

create or replace function public.get_available_qc_operators()
returns table(profile_id uuid,display_name text,verified boolean)
language plpgsql
security definer
set search_path=public
as $$
declare v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_role not in ('field_agent','admin') then raise exception 'Field-agent or admin access required'; end if;

  return query
  select p.id,p.display_name,p.verified
  from public.profiles p
  where p.role='qc_operator' and p.verified=true
  order by p.display_name,p.id;
end;
$$;

create or replace function public.get_qc_assignment_queue()
returns table(
  trade_id uuid,
  confirmation_reference text,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  origin_district text,
  destination_district text,
  agreed_quantity_kg numeric,
  delivery_due_at timestamptz,
  trade_status text,
  qc_operator_profile_id uuid,
  qc_operator_name text,
  qc_assigned_at timestamptz
)
language plpgsql
security definer
set search_path=public
as $$
declare v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if v_role not in ('field_agent','admin') then raise exception 'Field-agent or admin access required'; end if;

  return query
  select
    t.id,tc.reference,c.code,c.name_en,c.name_bn,lo.district,ld.district,
    t.agreed_quantity_kg,t.delivery_due_at,t.status::text,
    t.qc_operator_profile_id,q.display_name,t.qc_assigned_at
  from public.trades t
  join public.commodities c on c.id=t.commodity_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  join public.trade_confirmations tc on tc.trade_id=t.id and tc.qc_required=true
  left join public.profiles q on q.id=t.qc_operator_profile_id
  where t.status in ('confirmed','awaiting_qc')
  order by (t.qc_operator_profile_id is null) desc,t.delivery_due_at nulls last,t.created_at;
end;
$$;

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
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles p where p.auth_user_id=auth.uid() limit 1;
  if not found or v_profile.role not in ('qc_operator','admin') then raise exception 'QC operator access required'; end if;

  return query
  select
    t.id,tc.reference,c.code,c.name_en,c.name_bn,g.code,lo.district,ld.district,
    t.agreed_quantity_kg,t.agreed_price_bdt_per_kg,t.delivery_due_at,t.status::text,coalesce(tc.qc_required,true)
  from public.trades t
  join public.commodities c on c.id=t.commodity_id
  left join public.commodity_grades g on g.id=t.grade_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  join public.trade_confirmations tc on tc.trade_id=t.id
  where t.status in ('confirmed','awaiting_qc')
    and coalesce(tc.qc_required,true)=true
    and (v_profile.role='admin' or t.qc_operator_profile_id=v_profile.id)
  order by t.delivery_due_at nulls last,t.created_at;
end;
$$;

revoke all on function public.get_available_qc_operators() from public,anon;
revoke all on function public.get_qc_assignment_queue() from public,anon;
revoke all on function public.get_qc_queue() from public,anon;

grant execute on function public.get_available_qc_operators() to authenticated;
grant execute on function public.get_qc_assignment_queue() to authenticated;
grant execute on function public.get_qc_queue() to authenticated;
