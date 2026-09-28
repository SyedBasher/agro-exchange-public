-- Agro-Exchange initial PostgreSQL schema
-- v0.3: core spot-market and market-intelligence data model

create extension if not exists pgcrypto;

create type user_role as enum ('farmer','field_agent','buyer','qc_operator','transporter','admin');
create type order_status as enum ('draft','open','matched','partially_matched','closed','cancelled');
create type match_status as enum ('proposed','accepted','rejected','expired','converted');
create type trade_status as enum ('confirmed','awaiting_qc','ready_for_dispatch','in_transit','delivered','settled','disputed','cancelled');
create type payment_status as enum ('pending','initiated','confirmed','failed','refunded');

create table profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,
  role user_role not null,
  display_name text not null,
  phone text,
  preferred_language text not null default 'bn' check (preferred_language in ('bn','en')),
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table locations (
  id uuid primary key default gen_random_uuid(),
  division text,
  district text not null,
  upazila text,
  market_name text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  created_at timestamptz not null default now()
);

create table farms (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references profiles(id),
  name text,
  location_id uuid references locations(id),
  acreage numeric(10,2),
  verified boolean not null default false,
  created_at timestamptz not null default now()
);

create table buyer_organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  buyer_type text,
  location_id uuid references locations(id),
  verified boolean not null default false,
  created_at timestamptz not null default now()
);

create table buyer_memberships (
  buyer_organization_id uuid not null references buyer_organizations(id) on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  primary key (buyer_organization_id, profile_id)
);

create table commodities (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name_en text not null,
  name_bn text not null,
  default_unit text not null default 'kg',
  active boolean not null default true
);

create table commodity_grades (
  id uuid primary key default gen_random_uuid(),
  commodity_id uuid not null references commodities(id) on delete cascade,
  code text not null,
  label_en text not null,
  label_bn text not null,
  specification jsonb not null default '{}'::jsonb,
  unique (commodity_id, code)
);

create table sell_offers (
  id uuid primary key default gen_random_uuid(),
  seller_profile_id uuid not null references profiles(id),
  farm_id uuid references farms(id),
  commodity_id uuid not null references commodities(id),
  grade_id uuid references commodity_grades(id),
  origin_location_id uuid not null references locations(id),
  quantity_kg numeric(14,2) not null check (quantity_kg > 0),
  remaining_quantity_kg numeric(14,2) not null check (remaining_quantity_kg >= 0),
  minimum_price_bdt_per_kg numeric(12,2),
  available_from date not null,
  available_until date,
  fulfilment_preference text,
  status order_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table buy_orders (
  id uuid primary key default gen_random_uuid(),
  buyer_organization_id uuid not null references buyer_organizations(id),
  created_by_profile_id uuid not null references profiles(id),
  commodity_id uuid not null references commodities(id),
  grade_id uuid references commodity_grades(id),
  destination_location_id uuid not null references locations(id),
  quantity_kg numeric(14,2) not null check (quantity_kg > 0),
  remaining_quantity_kg numeric(14,2) not null check (remaining_quantity_kg >= 0),
  target_price_bdt_per_kg numeric(12,2),
  delivery_from date not null,
  delivery_until date,
  status order_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table matches (
  id uuid primary key default gen_random_uuid(),
  sell_offer_id uuid not null references sell_offers(id),
  buy_order_id uuid not null references buy_orders(id),
  matched_quantity_kg numeric(14,2) not null check (matched_quantity_kg > 0),
  proposed_price_bdt_per_kg numeric(12,2),
  estimated_collection_cost_bdt_per_kg numeric(12,2),
  estimated_qc_cost_bdt_per_kg numeric(12,2),
  estimated_transport_cost_bdt_per_kg numeric(12,2),
  estimated_delivered_cost_bdt_per_kg numeric(12,2),
  score numeric(6,3),
  scoring_version text,
  scoring_factors jsonb not null default '{}'::jsonb,
  status match_status not null default 'proposed',
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (sell_offer_id, buy_order_id, created_at)
);

create table trades (
  id uuid primary key default gen_random_uuid(),
  match_id uuid unique references matches(id),
  seller_profile_id uuid not null references profiles(id),
  buyer_organization_id uuid not null references buyer_organizations(id),
  commodity_id uuid not null references commodities(id),
  grade_id uuid references commodity_grades(id),
  origin_location_id uuid not null references locations(id),
  destination_location_id uuid not null references locations(id),
  agreed_quantity_kg numeric(14,2) not null check (agreed_quantity_kg > 0),
  agreed_price_bdt_per_kg numeric(12,2) not null check (agreed_price_bdt_per_kg >= 0),
  delivery_due_at timestamptz,
  payment_terms text,
  status trade_status not null default 'confirmed',
  confirmed_at timestamptz not null default now(),
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table qc_records (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  operator_profile_id uuid not null references profiles(id),
  location_id uuid references locations(id),
  measured_weight_kg numeric(14,2) not null check (measured_weight_kg > 0),
  accepted_grade_id uuid references commodity_grades(id),
  accepted boolean not null,
  notes text,
  photo_urls jsonb not null default '[]'::jsonb,
  recorded_at timestamptz not null default now()
);

create table shipments (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  transporter_profile_id uuid references profiles(id),
  vehicle_reference text,
  pickup_location_id uuid references locations(id),
  delivery_location_id uuid references locations(id),
  transport_cost_bdt numeric(14,2),
  dispatched_at timestamptz,
  delivered_at timestamptz,
  proof_of_delivery jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  method text,
  external_reference text,
  amount_bdt numeric(16,2) not null check (amount_bdt >= 0),
  status payment_status not null default 'pending',
  initiated_at timestamptz,
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create table trade_status_events (
  id bigint generated always as identity primary key,
  trade_id uuid not null references trades(id) on delete cascade,
  status trade_status not null,
  changed_by_profile_id uuid references profiles(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table market_observations (
  id bigint generated always as identity primary key,
  commodity_id uuid not null references commodities(id),
  grade_id uuid references commodity_grades(id),
  location_id uuid not null references locations(id),
  observed_at timestamptz not null,
  observation_type text not null,
  price_bdt_per_kg numeric(12,2),
  quantity_kg numeric(16,2),
  source_type text not null,
  source_reference text,
  verified boolean not null default false,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index sell_offers_matching_idx on sell_offers (commodity_id, status, available_from, origin_location_id);
create index buy_orders_matching_idx on buy_orders (commodity_id, status, delivery_from, destination_location_id);
create index matches_status_idx on matches (status, created_at desc);
create index trades_status_idx on trades (status, created_at desc);
create index market_observations_lookup_idx on market_observations (commodity_id, location_id, observed_at desc);

insert into commodities(code,name_en,name_bn,default_unit) values
('POTATO','Potato','আলু','kg'),
('ONION','Onion','পেঁয়াজ','kg'),
('RICE','Rice','চাল','kg')
on conflict (code) do nothing;
