-- Agro-Exchange v1.9 — commercial integrity and authority hardening.
-- Closes R2-04 and the silent quantity/price parts of R2-05 while keeping
-- commercial changes explicit and mutually accepted.

-- ---------------------------------------------------------------------------
-- 1. Database invariants for positive commercial prices.
-- ---------------------------------------------------------------------------
alter table public.sell_offers
  drop constraint if exists sell_offers_minimum_price_positive_v1_9;
alter table public.sell_offers
  add constraint sell_offers_minimum_price_positive_v1_9
  check (minimum_price_bdt_per_kg is null or minimum_price_bdt_per_kg>0);

alter table public.buy_orders
  drop constraint if exists buy_orders_target_price_positive_v1_9;
alter table public.buy_orders
  add constraint buy_orders_target_price_positive_v1_9
  check (target_price_bdt_per_kg is null or target_price_bdt_per_kg>0);

alter table public.trade_confirmations
  drop constraint if exists trade_confirmations_agreed_price_bdt_per_kg_check;
alter table public.trade_confirmations
  add constraint trade_confirmations_agreed_price_bdt_per_kg_check
  check (agreed_price_bdt_per_kg>0);

alter table public.trade_adjustment_proposals
  drop constraint if exists trade_adjustment_proposals_proposed_unit_price_bdt_per_kg_check;
alter table public.trade_adjustment_proposals
  add constraint trade_adjustment_proposals_proposed_unit_price_bdt_per_kg_check
  check (proposed_unit_price_bdt_per_kg is null or proposed_unit_price_bdt_per_kg>0);

-- ---------------------------------------------------------------------------
-- 2. Buyer membership is an active authority token, not a permanent badge.
--    A membership can exist only while both profile and organization remain
--    eligible. Demotion/unverification automatically revokes it.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_buyer_membership_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_profile public.profiles%rowtype;v_org public.buyer_organizations%rowtype;
begin
  select * into v_profile from public.profiles where id=new.profile_id;
  if not found or v_profile.role<>'buyer' or not v_profile.verified then
    raise exception 'Buyer membership requires a verified buyer profile';
  end if;
  select * into v_org from public.buyer_organizations where id=new.buyer_organization_id;
  if not found or not v_org.verified then
    raise exception 'Buyer membership requires a verified buyer organization';
  end if;
  return new;
end;
$$;

drop trigger if exists buyer_membership_integrity_v1_9 on public.buyer_memberships;
create trigger buyer_membership_integrity_v1_9
before insert or update on public.buyer_memberships
for each row execute function public.enforce_buyer_membership_integrity();

create or replace function public.revoke_membership_if_profile_ineligible()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.role<>'buyer' or not new.verified then
    delete from public.buyer_memberships where profile_id=new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists revoke_buyer_membership_on_profile_change_v1_9 on public.profiles;
create trigger revoke_buyer_membership_on_profile_change_v1_9
after update of role,verified on public.profiles
for each row
when (old.role is distinct from new.role or old.verified is distinct from new.verified)
execute function public.revoke_membership_if_profile_ineligible();

create or replace function public.revoke_memberships_if_org_ineligible()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if not new.verified then
    delete from public.buyer_memberships where buyer_organization_id=new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists revoke_buyer_memberships_on_org_change_v1_9 on public.buyer_organizations;
create trigger revoke_buyer_memberships_on_org_change_v1_9
after update of verified on public.buyer_organizations
for each row
when (old.verified is distinct from new.verified)
execute function public.revoke_memberships_if_org_ineligible();

create or replace function public.admin_revoke_buyer_membership(
  p_profile_id uuid,
  p_buyer_organization_id uuid,
  p_note text default null
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare v_admin public.profiles%rowtype;v_deleted integer;
begin
  v_admin:=public.require_admin_profile();
  delete from public.buyer_memberships
  where profile_id=p_profile_id and buyer_organization_id=p_buyer_organization_id;
  get diagnostics v_deleted=row_count;
  if v_deleted>0 then
    insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
    values(v_admin.id,'buyer_membership_revoked','profile',p_profile_id,
      jsonb_build_object('buyer_organization_id',p_buyer_organization_id,'note',nullif(btrim(coalesce(p_note,'')),''))
    );
  end if;
  return v_deleted>0;
end;
$$;

-- Internal trigger helpers are never browser RPCs.
revoke all on function public.enforce_buyer_membership_integrity() from public,anon,authenticated;
revoke all on function public.revoke_membership_if_profile_ineligible() from public,anon,authenticated;
revoke all on function public.revoke_memberships_if_org_ineligible() from public,anon,authenticated;
revoke all on function public.admin_revoke_buyer_membership(uuid,uuid,text) from public,anon;
grant execute on function public.admin_revoke_buyer_membership(uuid,uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Proposal expiry behaves as an actual lifecycle rule.
-- ---------------------------------------------------------------------------
create or replace function public.expire_stale_confirmation_for_pair()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  update public.trade_confirmations
  set status='expired',updated_at=now()
  where sell_offer_id=new.sell_offer_id
    and buy_order_id=new.buy_order_id
    and status in ('proposed','seller_accepted','buyer_accepted')
    and expires_at is not null
    and expires_at<now();
  return new;
end;
$$;

drop trigger if exists expire_stale_confirmation_before_insert_v1_9 on public.trade_confirmations;
create trigger expire_stale_confirmation_before_insert_v1_9
before insert on public.trade_confirmations
for each row execute function public.expire_stale_confirmation_for_pair();

revoke all on function public.expire_stale_confirmation_for_pair() from public,anon,authenticated;

create or replace function public.get_my_trade_confirmations()
returns table(
  confirmation_id uuid,
  confirmation_reference text,
  confirmation_status text,
  commodity_code text,
  commodity_name_en text,
  commodity_name_bn text,
  origin_district text,
  destination_district text,
  agreed_quantity_kg numeric,
  agreed_price_bdt_per_kg numeric,
  delivery_due_at timestamptz,
  payment_terms text,
  qc_required boolean,
  seller_accepted boolean,
  buyer_accepted boolean,
  trade_id uuid,
  created_at timestamptz
)
language sql
security definer
set search_path=public
as $$
  select
    tc.id,
    tc.reference,
    case
      when tc.status in ('proposed','seller_accepted','buyer_accepted')
       and tc.expires_at is not null and tc.expires_at<now()
      then 'expired'
      else tc.status
    end,
    c.code,c.name_en,c.name_bn,lo.district,ld.district,
    tc.agreed_quantity_kg,tc.agreed_price_bdt_per_kg,tc.delivery_due_at,
    tc.payment_terms,tc.qc_required,
    tc.seller_accepted_at is not null,
    tc.buyer_accepted_at is not null,
    tc.trade_id,tc.created_at
  from public.trade_confirmations tc
  join public.commodities c on c.id=tc.commodity_id
  join public.locations lo on lo.id=tc.origin_location_id
  join public.locations ld on ld.id=tc.destination_location_id
  where auth.uid() is not null
    and (
      tc.seller_profile_id=(select id from public.profiles where auth_user_id=auth.uid())
      or exists(
        select 1 from public.buyer_memberships bm
        join public.profiles p on p.id=bm.profile_id
        where p.auth_user_id=auth.uid()
          and bm.buyer_organization_id=tc.buyer_organization_id
      )
    )
  order by tc.created_at desc;
$$;

revoke all on function public.get_my_trade_confirmations() from public,anon;
grant execute on function public.get_my_trade_confirmations() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Buyer receipt is commercial consent. Admin cannot substitute. If measured
--    received quantity differs from the active contract basis, the buyer must
--    report a discrepancy and use the mutual adjustment flow; quantity never
--    silently rewrites the amount due.
-- ---------------------------------------------------------------------------
create or replace function public.confirm_delivery_receipt(
  p_trade_id uuid,
  p_received_quantity_kg numeric default null,
  p_accepted boolean default true,
  p_notes text default null,
  p_discrepancy_reason text default null
)
returns table(receipt_id uuid,receipt_status text,obligation_id uuid,amount_due_bdt numeric,trade_status text)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;v_trade public.trades%rowtype;v_shipment public.shipments%rowtype;
  v_receipt public.delivery_receipts%rowtype;v_obligation public.payment_obligations%rowtype;
  v_basis_qty numeric(14,2);v_basis_price numeric(12,2);v_amount numeric(16,2);v_is_buyer boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;
  if v_trade.status<>'delivered' then raise exception 'Trade must be delivered before buyer receipt confirmation'; end if;

  v_is_buyer:=v_profile.role='buyer' and v_profile.verified and exists(
    select 1
    from public.buyer_memberships bm
    join public.buyer_organizations org on org.id=bm.buyer_organization_id
    where bm.profile_id=v_profile.id
      and bm.buyer_organization_id=v_trade.buyer_organization_id
      and org.verified=true
  );
  if not v_is_buyer then raise exception 'Verified buyer organization confirmation required'; end if;

  if p_received_quantity_kg is not null and p_received_quantity_kg<=0 then
    raise exception 'Received quantity must be greater than zero';
  end if;
  if not coalesce(p_accepted,true) and nullif(btrim(coalesce(p_discrepancy_reason,'')),'') is null then
    raise exception 'Discrepancy reason is required when delivery is disputed';
  end if;
  if exists(select 1 from public.delivery_receipts where trade_id=p_trade_id) then
    raise exception 'Delivery receipt has already been recorded for this trade';
  end if;

  select * into v_shipment
  from public.shipments
  where trade_id=p_trade_id and status='delivered'
  order by delivered_at desc nulls last,created_at desc
  limit 1;
  if not found then raise exception 'Delivered shipment not found'; end if;

  v_basis_qty:=v_trade.agreed_quantity_kg;
  v_basis_price:=v_trade.agreed_price_bdt_per_kg;
  select p.proposed_quantity_kg,p.proposed_unit_price_bdt_per_kg
    into v_basis_qty,v_basis_price
  from public.trade_adjustment_proposals p
  join public.trade_disputes d on d.id=p.dispute_id
  where d.trade_id=v_trade.id and p.status='accepted' and p.applied_at is not null
    and p.resolution_type in ('revise_terms','partial_rejection','accept_original')
  order by p.applied_at desc limit 1;
  v_basis_qty:=coalesce(v_basis_qty,v_trade.agreed_quantity_kg);
  v_basis_price:=coalesce(v_basis_price,v_trade.agreed_price_bdt_per_kg);

  if coalesce(p_accepted,true)
     and p_received_quantity_kg is not null
     and abs(p_received_quantity_kg-v_basis_qty)>0.01 then
    raise exception 'Received quantity differs from the agreed quantity. Report a discrepancy so both parties can approve any commercial adjustment';
  end if;

  insert into public.delivery_receipts(
    trade_id,shipment_id,buyer_organization_id,confirmed_by_profile_id,received_quantity_kg,status,notes,discrepancy_reason
  ) values(
    v_trade.id,v_shipment.id,v_trade.buyer_organization_id,v_profile.id,
    coalesce(p_received_quantity_kg,v_basis_qty),
    case when coalesce(p_accepted,true) then 'accepted' else 'disputed' end,
    nullif(btrim(coalesce(p_notes,'')),''),
    nullif(btrim(coalesce(p_discrepancy_reason,'')),'')
  ) returning * into v_receipt;

  v_amount:=round(v_basis_qty*v_basis_price,2);
  insert into public.payment_obligations(
    trade_id,buyer_organization_id,basis_quantity_kg,unit_price_bdt_per_kg,amount_due_bdt,status,due_at
  ) values(
    v_trade.id,v_trade.buyer_organization_id,v_basis_qty,v_basis_price,v_amount,
    case when v_receipt.status='accepted' then 'due' else 'disputed' end,
    case when v_receipt.status='accepted' then now() else null end
  ) returning * into v_obligation;

  if v_receipt.status='disputed' then
    update public.trades set status='disputed',updated_at=now() where id=v_trade.id;
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade.id,'disputed',v_profile.id,jsonb_build_object(
      'event_type','buyer_receipt_disputed','receipt_id',v_receipt.id,
      'reason',v_receipt.discrepancy_reason,'received_quantity_kg',v_receipt.received_quantity_kg,
      'contract_basis_quantity_kg',v_basis_qty
    ));
  else
    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(v_trade.id,'delivered',v_profile.id,jsonb_build_object(
      'event_type','buyer_receipt_accepted','receipt_id',v_receipt.id,
      'payment_obligation_id',v_obligation.id,'amount_due_bdt',v_amount,
      'basis_quantity_kg',v_basis_qty,'basis_unit_price_bdt_per_kg',v_basis_price
    ));
  end if;

  return query select v_receipt.id,v_receipt.status,v_obligation.id,v_obligation.amount_due_bdt,
    (select t.status::text from public.trades t where t.id=v_trade.id);
end;
$$;

revoke all on function public.confirm_delivery_receipt(uuid,numeric,boolean,text,text) from public,anon;
grant execute on function public.confirm_delivery_receipt(uuid,numeric,boolean,text,text) to authenticated;
