-- Agro-Exchange v1.6: register DAM official source and preserve a source-backed raw snapshot.
-- Values below were transcribed from the public DAM headline page during implementation.
-- The captured headline did not identify a specific market/effective date, so these
-- records intentionally remain unpromoted and are not represented as live trade prices.

insert into public.market_data_sources(
  code,name,publisher,authority_class,homepage_url,report_url,retrieval_method,access_status,notes
) values (
  'DAM_BD_DAILY',
  'Daily Market Price Report',
  'Department of Agricultural Marketing, Ministry of Agriculture, Bangladesh',
  'official',
  'https://market.dam.gov.bd/',
  'https://market.dam.gov.bd/market_daily_price_report',
  'manual_html',
  'reuse_review_pending',
  'Official public webpage. Automated systematic reuse should be reviewed before production scraping; v1.6 stores a manual source snapshot with provenance.'
)
on conflict (code) do update set
  name=excluded.name,publisher=excluded.publisher,homepage_url=excluded.homepage_url,
  report_url=excluded.report_url,active=true,updated_at=now();

do $$
declare
  v_source_id uuid;
  v_run_id uuid;
  v_onion uuid;
  v_rice uuid;
begin
  select id into v_source_id from public.market_data_sources where code='DAM_BD_DAILY';
  select id into v_onion from public.commodities where code='ONION';
  select id into v_rice from public.commodities where code='RICE';

  insert into public.market_source_runs(source_id,source_url,status,notes)
  values(v_source_id,'https://market.dam.gov.bd/market_daily_price_report','parsed',
    'Manual v1.6 capture of the public headline ticker. Retrieval time is recorded; effective market/date was not explicit in the captured headline text.')
  returning id into v_run_id;

  insert into public.market_source_records(
    run_id,source_record_key,commodity_label,commodity_id,grade_label,geography_label,price_type,price_low,price_high,unit_text,mapping_status,raw_payload
  ) values
    (v_run_id,'ONION_LOCAL_HEADLINE','Onion-local',v_onion,'Local','Headline ticker; market not specified','retail',60,64,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Onion-local')),
    (v_run_id,'AMAN_FINE_HEADLINE','Aman-Fine',v_rice,'Aman-Fine','Headline ticker; market not specified','retail',72,75,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Aman-Fine')),
    (v_run_id,'AMAN_MEDIUM_HEADLINE','Aman-Medium',v_rice,'Aman-Medium','Headline ticker; market not specified','retail',56,60,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Aman-Medium')),
    (v_run_id,'AMAN_COARSE_HEADLINE','Aman-Coarse',v_rice,'Aman-Coarse','Headline ticker; market not specified','retail',48,50,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Aman-Coarse')),
    (v_run_id,'BORO_FINE_HEADLINE','Boro-Fine',v_rice,'Boro-Fine','Headline ticker; market not specified','retail',66,70,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Boro-Fine')),
    (v_run_id,'BORO_MEDIUM_HEADLINE','Boro-Medium',v_rice,'Boro-Medium','Headline ticker; market not specified','retail',55,57,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Boro-Medium')),
    (v_run_id,'BORO_COARSE_HEADLINE','Boro-Coarse',v_rice,'Boro-Coarse','Headline ticker; market not specified','retail',47,49,'BDT/kg','commodity_mapped',jsonb_build_object('source_label','Boro-Coarse'));

  update public.market_source_runs set record_count=7 where id=v_run_id;
end $$;
