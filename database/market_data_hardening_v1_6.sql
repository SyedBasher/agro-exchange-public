-- Agro-Exchange v1.6 market-source hardening.
-- Public/source-card users can read only explicit provenance columns; raw_payload,
-- internal notes and content hashes are not exposed through direct PostgREST access.

revoke all on public.market_data_sources from anon,authenticated;
revoke all on public.market_source_runs from anon,authenticated;
revoke all on public.market_source_records from anon,authenticated;

grant select (
  id,code,name,publisher,authority_class,homepage_url,report_url,
  retrieval_method,access_status,active,created_at,updated_at
) on public.market_data_sources to anon,authenticated;

grant select (
  id,source_id,source_url,retrieved_at,effective_date,status,record_count,created_at
) on public.market_source_runs to anon,authenticated;

grant select (
  id,run_id,source_record_key,commodity_label,commodity_id,grade_label,grade_id,
  geography_label,location_id,price_type,price_low,price_high,unit_text,observed_at,
  mapping_status,promoted_observation_id,created_at
) on public.market_source_records to anon,authenticated;

-- Re-create promotion with an explicit source-reuse gate. Source values may remain
-- visible as attributed raw captures while reuse status is pending, but they cannot
-- be promoted into verified public market observations until the source status is cleared.
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
  if upper(replace(v_record.unit_text,' ','')) not in ('BDT/KG','TK/KG') then
    raise exception 'Only BDT/kg source records can be promoted without an explicit unit conversion';
  end if;
  if v_record.price_low is null and v_record.price_high is null then
    raise exception 'A source price is required before promotion';
  end if;

  select * into v_run from public.market_source_runs where id=v_record.run_id;
  select * into v_source from public.market_data_sources where id=v_run.source_id;
  if v_source.access_status='reuse_review_pending' then
    raise exception 'Source reuse status must be cleared before promotion to a verified market observation';
  end if;

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
