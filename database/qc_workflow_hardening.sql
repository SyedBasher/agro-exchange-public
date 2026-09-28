-- Agro-Exchange v1.0 QC hardening after initial workflow migration.
-- Adds data-level invariants and the index used by trade-level QC history.

create index if not exists qc_records_trade_recorded_idx
  on public.qc_records(trade_id,recorded_at desc);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='qc_records_certified_scale_reference'
      and conrelid='public.qc_records'::regclass
  ) then
    alter table public.qc_records
      add constraint qc_records_certified_scale_reference
      check (not certified_scale or nullif(btrim(scale_reference),'') is not null);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname='qc_records_weighing_method_allowed'
      and conrelid='public.qc_records'::regclass
  ) then
    alter table public.qc_records
      add constraint qc_records_weighing_method_allowed
      check (weighing_method in ('digital_scale','warehouse_scale','other'));
  end if;
end $$;

create or replace function public.enforce_trade_qc_required()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_required boolean;
begin
  select coalesce(tc.qc_required,true) into v_required
  from public.trade_confirmations tc
  where tc.trade_id=new.trade_id
  limit 1;

  if coalesce(v_required,true)=false then
    raise exception 'QC is not required for this trade';
  end if;
  return new;
end;
$$;

drop trigger if exists qc_records_require_qc_trade on public.qc_records;
create trigger qc_records_require_qc_trade
before insert on public.qc_records
for each row execute function public.enforce_trade_qc_required();

revoke all on function public.enforce_trade_qc_required() from public,anon,authenticated;
