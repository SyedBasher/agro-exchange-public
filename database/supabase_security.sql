-- Agro-Exchange Supabase row-level security baseline
-- Apply after schema.sql and views.sql.
-- Designed for authenticated marketplace users; service-role access remains server-side only.

create or replace function current_profile_id()
returns uuid
language sql
stable
security definer
set search_path=public
as $$
  select id from profiles where auth_user_id=auth.uid() limit 1
$$;

create or replace function current_user_role()
returns user_role
language sql
stable
security definer
set search_path=public
as $$
  select role from profiles where auth_user_id=auth.uid() limit 1
$$;

alter table profiles enable row level security;
alter table farms enable row level security;
alter table buyer_organizations enable row level security;
alter table buyer_memberships enable row level security;
alter table locations enable row level security;
alter table commodities enable row level security;
alter table commodity_grades enable row level security;
alter table sell_offers enable row level security;
alter table buy_orders enable row level security;
alter table matches enable row level security;
alter table trades enable row level security;
alter table qc_records enable row level security;
alter table shipments enable row level security;
alter table payments enable row level security;
alter table trade_status_events enable row level security;
alter table market_observations enable row level security;

-- Reference data are safe to read.
create policy locations_read on locations for select to anon,authenticated using (true);
create policy commodities_read on commodities for select to anon,authenticated using (active=true);
create policy commodity_grades_read on commodity_grades for select to anon,authenticated using (true);

-- A user can see and maintain only their own profile.
create policy profiles_select_own on profiles for select to authenticated using (auth_user_id=auth.uid());
create policy profiles_insert_own on profiles for insert to authenticated with check (auth_user_id=auth.uid());
create policy profiles_update_own on profiles for update to authenticated using (auth_user_id=auth.uid()) with check (auth_user_id=auth.uid());

-- Farms belong to a profile.
create policy farms_select_own on farms for select to authenticated using (owner_profile_id=current_profile_id());
create policy farms_insert_own on farms for insert to authenticated with check (owner_profile_id=current_profile_id());
create policy farms_update_own on farms for update to authenticated using (owner_profile_id=current_profile_id()) with check (owner_profile_id=current_profile_id());

-- Buyer organization identity is marketplace reference data.
create policy buyer_orgs_read on buyer_organizations for select to authenticated using (true);
create policy buyer_memberships_read_own on buyer_memberships for select to authenticated using (profile_id=current_profile_id());

-- Open supply is visible to authenticated participants; sellers retain access to their own non-open rows.
create policy sell_offers_read on sell_offers for select to authenticated using (
  status in ('open','matched','partially_matched') or seller_profile_id=current_profile_id()
);
create policy sell_offers_insert_own on sell_offers for insert to authenticated with check (
  seller_profile_id=current_profile_id()
);
create policy sell_offers_update_own on sell_offers for update to authenticated using (
  seller_profile_id=current_profile_id()
) with check (seller_profile_id=current_profile_id());

-- Open demand is visible to authenticated participants; organization members can also see their closed/draft orders.
create policy buy_orders_read on buy_orders for select to authenticated using (
  status in ('open','matched','partially_matched')
  or exists (
    select 1 from buyer_memberships bm
    where bm.buyer_organization_id=buy_orders.buyer_organization_id
      and bm.profile_id=current_profile_id()
  )
);
create policy buy_orders_insert_member on buy_orders for insert to authenticated with check (
  created_by_profile_id=current_profile_id()
  and exists (
    select 1 from buyer_memberships bm
    where bm.buyer_organization_id=buy_orders.buyer_organization_id
      and bm.profile_id=current_profile_id()
  )
);
create policy buy_orders_update_member on buy_orders for update to authenticated using (
  exists (
    select 1 from buyer_memberships bm
    where bm.buyer_organization_id=buy_orders.buyer_organization_id
      and bm.profile_id=current_profile_id()
  )
);

-- Matches and trades are visible only to their seller or buyer organization members.
create policy matches_read_participant on matches for select to authenticated using (
  exists (select 1 from sell_offers s where s.id=matches.sell_offer_id and s.seller_profile_id=current_profile_id())
  or exists (
    select 1 from buy_orders b
    join buyer_memberships bm on bm.buyer_organization_id=b.buyer_organization_id
    where b.id=matches.buy_order_id and bm.profile_id=current_profile_id()
  )
);

create policy trades_read_participant on trades for select to authenticated using (
  seller_profile_id=current_profile_id()
  or exists (
    select 1 from buyer_memberships bm
    where bm.buyer_organization_id=trades.buyer_organization_id
      and bm.profile_id=current_profile_id()
  )
);

create policy qc_read_trade_participant on qc_records for select to authenticated using (
  exists (select 1 from trades t where t.id=qc_records.trade_id and (
    t.seller_profile_id=current_profile_id()
    or exists (select 1 from buyer_memberships bm where bm.buyer_organization_id=t.buyer_organization_id and bm.profile_id=current_profile_id())
  ))
  or operator_profile_id=current_profile_id()
);

create policy shipments_read_trade_participant on shipments for select to authenticated using (
  transporter_profile_id=current_profile_id()
  or exists (select 1 from trades t where t.id=shipments.trade_id and (
    t.seller_profile_id=current_profile_id()
    or exists (select 1 from buyer_memberships bm where bm.buyer_organization_id=t.buyer_organization_id and bm.profile_id=current_profile_id())
  ))
);

create policy payments_read_trade_participant on payments for select to authenticated using (
  exists (select 1 from trades t where t.id=payments.trade_id and (
    t.seller_profile_id=current_profile_id()
    or exists (select 1 from buyer_memberships bm where bm.buyer_organization_id=t.buyer_organization_id and bm.profile_id=current_profile_id())
  ))
);

create policy trade_events_read_participant on trade_status_events for select to authenticated using (
  exists (select 1 from trades t where t.id=trade_status_events.trade_id and (
    t.seller_profile_id=current_profile_id()
    or exists (select 1 from buyer_memberships bm where bm.buyer_organization_id=t.buyer_organization_id and bm.profile_id=current_profile_id())
  ))
);

-- Only verified market observations are public. Authenticated users may read all observations,
-- including clearly flagged simulated/pilot observations.
create policy market_obs_public_verified on market_observations for select to anon using (verified=true);
create policy market_obs_authenticated on market_observations for select to authenticated using (true);

grant usage on schema public to anon,authenticated;
grant select on locations,commodities,commodity_grades to anon,authenticated;
grant select on buyer_organizations,sell_offers,buy_orders,matches,trades,qc_records,shipments,payments,trade_status_events,market_observations to authenticated;
grant select,insert,update on profiles,farms to authenticated;
grant insert,update on sell_offers,buy_orders to authenticated;
grant select on buyer_memberships to authenticated;
