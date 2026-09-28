-- Agro-Exchange v1.2 settlement performance hardening
-- Addresses new-table RLS initplan and foreign-key index findings.

create index if not exists delivery_receipts_confirmed_by_idx on public.delivery_receipts(confirmed_by_profile_id);
create index if not exists payment_obligations_buyer_org_idx on public.payment_obligations(buyer_organization_id);
create index if not exists payments_recorded_by_idx on public.payments(recorded_by_profile_id);
create index if not exists payments_confirmed_by_idx on public.payments(confirmed_by_profile_id);

drop policy if exists delivery_receipts_participant_read on public.delivery_receipts;
create policy delivery_receipts_participant_read on public.delivery_receipts
for select to authenticated
using (
  exists (
    select 1 from public.trades t
    where t.id=delivery_receipts.trade_id
      and (
        t.seller_profile_id=(select id from public.profiles where auth_user_id=(select auth.uid()))
        or exists (
          select 1 from public.buyer_memberships bm
          join public.profiles p on p.id=bm.profile_id
          where p.auth_user_id=(select auth.uid()) and bm.buyer_organization_id=t.buyer_organization_id
        )
        or exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
      )
  )
);

drop policy if exists payment_obligations_participant_read on public.payment_obligations;
create policy payment_obligations_participant_read on public.payment_obligations
for select to authenticated
using (
  exists (
    select 1 from public.trades t
    where t.id=payment_obligations.trade_id
      and (
        t.seller_profile_id=(select id from public.profiles where auth_user_id=(select auth.uid()))
        or exists (
          select 1 from public.buyer_memberships bm
          join public.profiles p on p.id=bm.profile_id
          where p.auth_user_id=(select auth.uid()) and bm.buyer_organization_id=t.buyer_organization_id
        )
        or exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
      )
  )
);
