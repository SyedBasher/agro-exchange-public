-- v1.6 follow-up after Supabase performance advisor.
create index if not exists market_source_records_grade_idx
  on public.market_source_records(grade_id);
