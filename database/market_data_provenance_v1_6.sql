-- Agro-Exchange v1.6: sourced market-data provenance and controlled promotion
-- Raw source captures are kept separate from normalized verified market observations.

create table if not exists public.market_data_sources (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  publisher text not null,
  authority_class text not null check (authority_class in ('official','partner','platform','manual')),
  homepage_url text,
  report_url text,
  retrieval_method text not null check (retrieval_method in ('manual_html','manual_csv','api','partner_feed','platform_generated')),
  access_status text not null default 'reuse_review_pending' check (access_status in ('reuse_review_pending','permission_granted','api_terms','platform_owned')),
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.market_source_runs (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.market_data_sources(id) on delete cascade,
  source_url text not null,
  retrieved_at timestamptz not null default now(),
  effective_date date,
  status text not null default 'captured' check (status in ('captured','parsed','promoted','failed')),
  content_hash text,
  record_count integer not null default 0 check (record_count >= 0),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.market_source_records (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.market_source_runs(id) on delete cascade,
  source_record_key text not null,
  commodity_label text not null,
  commodity_id uuid references public.commodities(id),
  grade_label text,
  grade_id uuid references public.commodity_grades(id),
  geography_label text,
  location_id uuid references public.locations(id),
  price_type text not null default 'unknown' check (price_type in ('farmgate','wholesale','retail','trade','unknown')),
  price_low numeric(12,2),
  price_high numeric(12,2),
  unit_text text not null default 'BDT/kg',
  observed_at timestamptz,
  raw_payload jsonb not null default '{}'::jsonb,
  mapping_status text not null default 'raw' check (mapping_status in ('raw','commodity_mapped','fully_mapped','promoted','rejected')),
  promoted_observation_id bigint unique references public.market_observations(id),
  created_at timestamptz not null default now(),
  unique(run_id,source_record_key),
  check (price_low is null or price_low >= 0),
  check (price_high is null or price_high >= 0),
  check (price_low is null or price_high is null or price_high >= price_low)
);

alter table public.market_observations
  add column if not exists market_source_id uuid references public.market_data_sources(id),
  add column if not exists source_run_id uuid references public.market_source_runs(id),
  add column if not exists source_record_id bigint references public.market_source_records(id),
  add column if not exists price_low_bdt_per_kg numeric(12,2),
  add column if not exists price_high_bdt_per_kg numeric(12,2),
  add column if not exists price_type text,
  add column if not exists source_unit text;

create index if not exists market_source_runs_source_retrieved_idx on public.market_source_runs(source_id,retrieved_at desc);
create index if not exists market_source_records_run_idx on public.market_source_records(run_id,id);
create index if not exists market_source_records_commodity_idx on public.market_source_records(commodity_id,observed_at desc);
create index if not exists market_source_records_location_idx on public.market_source_records(location_id,observed_at desc);
create index if not exists market_observations_source_idx on public.market_observations(market_source_id,observed_at desc);
create index if not exists market_observations_source_run_idx on public.market_observations(source_run_id);
create index if not exists market_observations_source_record_idx on public.market_observations(source_record_id);

alter table public.market_data_sources enable row level security;
alter table public.market_source_runs enable row level security;
alter table public.market_source_records enable row level security;

revoke all on public.market_data_sources from anon,authenticated;
revoke all on public.market_source_runs from anon,authenticated;
revoke all on public.market_source_records from anon,authenticated;
grant select on public.market_data_sources,public.market_source_runs,public.market_source_records to anon,authenticated;

drop policy if exists market_data_sources_public_read on public.market_data_sources;
create policy market_data_sources_public_read on public.market_data_sources
for select to anon,authenticated using (active=true);

drop policy if exists market_source_runs_public_read on public.market_source_runs;
create policy market_source_runs_public_read on public.market_source_runs
for select to anon,authenticated using (
  status <> 'failed'
  and exists(select 1 from public.market_data_sources s where s.id=market_source_runs.source_id and s.active=true)
);

drop policy if exists market_source_records_public_read on public.market_source_records;
create policy market_source_records_public_read on public.market_source_records
for select to anon,authenticated using (
  mapping_status <> 'rejected'
  and exists(
    select 1 from public.market_source_runs r
    join public.market_data_sources s on s.id=r.source_id
    where r.id=market_source_records.run_id and r.status<>'failed' and s.active=true
  )
);

create or replace view public.market_source_snapshot_view
with (security_invoker=true)
as
select
  r.id as source_record_id,
  s.code as source_code,
  s.name as source_name,
  s.publisher,
  s.authority_class,
  s.report_url,
  s.access_status,
  run.id as source_run_id,
  run.source_url,
  run.retrieved_at,
  run.effective_date,
  r.source_record_key,
  r.commodity_label,
  c.code as commodity_code,
  r.grade_label,
  r.geography_label,
  r.price_type,
  r.price_low,
  r.price_high,
  r.unit_text,
  r.observed_at,
  r.mapping_status
from public.market_source_records r
join public.market_source_runs run on run.id=r.run_id
join public.market_data_sources s on s.id=run.source_id
left join public.commodities c on c.id=r.commodity_id
where s.active=true and run.status<>'failed' and r.mapping_status<>'rejected';

grant select on public.market_source_snapshot_view to anon,authenticated;

create or replace function public.admin_promote_market_source_record(
  p_source_record_id bigint,
  p_location_id uuid,
  p_observed_at timestamptz,
  p_grade_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path=public
as $$
declare
  v_admin public.profiles%rowtype;
  v_record public.market_source_records%rowtype;
  v_run public.market_source_runs%rowtype;
  v_source public.market_data_sources%rowtype;
  v_observation_id bigint;
  v_mid numeric;
begin
  v_admin:=public.require_admin_profile();
  select * into v_record from public.market_source_records where id=p_source_record_id for update;
  if not found then raise exception 'Source record not found'; end if;
  if v_record.mapping_status='rejected' then raise exception 'Rejected source record cannot be promoted'; end if;
  if v_record.promoted_observation_id is not null then return v_record.promoted_observation_id; end if;
  if v_record.commodity_id is null then raise exception 'Commodity mapping is required before promotion'; end if;
  if p_location_id is null then raise exception 'Location is required before promotion'; end if;
  if p_observed_at is null then raise exception 'Observation timestamp is required before promotion'; end if;
  if upper(replace(v_record.unit_text,' ','')) not in ('BDT/KG','TK/KG') then raise exception 'Only BDT/kg source records can be promoted without an explicit unit conversion'; end if;
  if v_record.price_low is null and v_record.price_high is null then raise exception 'A source price is required before promotion'; end if;

  select * into v_run from public.market_source_runs where id=v_record.run_id;
  select * into v_source from public.market_data_sources where id=v_run.source_id;
  v_mid:=case when v_record.price_low is not null and v_record.price_high is not null
    then round((v_record.price_low+v_record.price_high)/2.0,2)
    else coalesce(v_record.price_low,v_record.price_high) end;

  insert into public.market_observations(
    commodity_id,grade_id,location_id,observed_at,observation_type,
    price_bdt_per_kg,source_type,source_reference,verified,provenance,
    market_source_id,source_run_id,source_record_id,price_low_bdt_per_kg,
    price_high_bdt_per_kg,price_type,source_unit
  ) values (
    v_record.commodity_id,coalesce(p_grade_id,v_record.grade_id),p_location_id,p_observed_at,'sourced_market_price',
    v_mid,'official_source',v_run.source_url,true,
    jsonb_build_object('source_code',v_source.code,'source_name',v_source.name,'publisher',v_source.publisher,
      'source_record_key',v_record.source_record_key,'retrieved_at',v_run.retrieved_at,
      'price_range_preserved',true,'promoted_by_profile_id',v_admin.id),
    v_source.id,v_run.id,v_record.id,v_record.price_low,v_record.price_high,v_record.price_type,v_record.unit_text
  ) returning id into v_observation_id;

  update public.market_source_records
  set location_id=p_location_id,grade_id=coalesce(p_grade_id,grade_id),observed_at=p_observed_at,
      mapping_status='promoted',promoted_observation_id=v_observation_id
  where id=v_record.id;

  if not exists(select 1 from public.market_source_records x where x.run_id=v_run.id and x.mapping_status not in ('promoted','rejected')) then
    update public.market_source_runs set status='promoted' where id=v_run.id;
  else
    update public.market_source_runs set status='parsed' where id=v_run.id and status='captured';
  end if;

  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'market_source_record_promoted','market_source_record',null,
    jsonb_build_object('source_record_id',v_record.id,'observation_id',v_observation_id,'location_id',p_location_id,'observed_at',p_observed_at));

  return v_observation_id;
end;
$$;

revoke all on function public.admin_promote_market_source_record(bigint,uuid,timestamptz,uuid) from public,anon;
grant execute on function public.admin_promote_market_source_record(bigint,uuid,timestamptz,uuid) to authenticated;
