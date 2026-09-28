-- Agro-Exchange v1.1 logistics hardening

create index if not exists shipments_assigned_by_idx
  on public.shipments(assigned_by_profile_id,assigned_at desc);
create index if not exists shipments_delivered_by_idx
  on public.shipments(delivered_by_profile_id,delivered_at desc);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='shipments_transport_cost_nonnegative' and conrelid='public.shipments'::regclass
  ) then
    alter table public.shipments add constraint shipments_transport_cost_nonnegative
      check (transport_cost_bdt is null or transport_cost_bdt >= 0);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname='shipments_proof_of_delivery_object' and conrelid='public.shipments'::regclass
  ) then
    alter table public.shipments add constraint shipments_proof_of_delivery_object
      check (jsonb_typeof(proof_of_delivery)='object');
  end if;
end $$;
