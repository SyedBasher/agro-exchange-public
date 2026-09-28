-- Agro-Exchange pilot seed data
-- Simulated development records only. Do not treat as live market data.

insert into locations(id,division,district,upazila,market_name,latitude,longitude) values
('10000000-0000-0000-0000-000000000001','Rajshahi','Bogra','Shibganj','Mahasthan pilot source',24.9650,89.3430),
('10000000-0000-0000-0000-000000000002','Rangpur','Rangpur','Rangpur Sadar','Rangpur pilot source',25.7439,89.2752),
('10000000-0000-0000-0000-000000000003','Rajshahi','Joypurhat','Joypurhat Sadar','Joypurhat pilot source',25.0968,89.0227),
('10000000-0000-0000-0000-000000000010','Dhaka','Dhaka',null,'Dhaka buyer market',23.8103,90.4125)
on conflict (id) do nothing;

insert into profiles(id,role,display_name,phone,preferred_language,verified) values
('20000000-0000-0000-0000-000000000001','farmer','Pilot Farmer A',null,'bn',true),
('20000000-0000-0000-0000-000000000002','farmer','Pilot Farmer B',null,'bn',true),
('20000000-0000-0000-0000-000000000003','farmer','Pilot Farmer C',null,'bn',true),
('20000000-0000-0000-0000-000000000010','buyer','Pilot Buyer User A',null,'en',true),
('20000000-0000-0000-0000-000000000011','buyer','Pilot Buyer User B',null,'en',true),
('20000000-0000-0000-0000-000000000012','buyer','Pilot Buyer User C',null,'en',true)
on conflict (id) do nothing;

insert into buyer_organizations(id,name,buyer_type,location_id,verified) values
('30000000-0000-0000-0000-000000000001','Dhaka Fresh Wholesale','Wholesaler','10000000-0000-0000-0000-000000000010',true),
('30000000-0000-0000-0000-000000000002','Metro Retail Distribution','Retail distributor','10000000-0000-0000-0000-000000000010',true),
('30000000-0000-0000-0000-000000000003','Eastern Foods Processing','Processor','10000000-0000-0000-0000-000000000010',true)
on conflict (id) do nothing;

insert into buyer_memberships(buyer_organization_id,profile_id) values
('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000010'),
('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000011'),
('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000012')
on conflict do nothing;

insert into commodity_grades(id,commodity_id,code,label_en,label_bn,specification)
select '40000000-0000-0000-0000-000000000001',id,'A','Grade A','গ্রেড A','{"prototype":true}'::jsonb from commodities where code='POTATO'
on conflict (id) do nothing;
insert into commodity_grades(id,commodity_id,code,label_en,label_bn,specification)
select '40000000-0000-0000-0000-000000000002',id,'A','Grade A','গ্রেড A','{"prototype":true}'::jsonb from commodities where code='ONION'
on conflict (id) do nothing;
insert into commodity_grades(id,commodity_id,code,label_en,label_bn,specification)
select '40000000-0000-0000-0000-000000000003',id,'STD','Standard','স্ট্যান্ডার্ড','{"prototype":true}'::jsonb from commodities where code='RICE'
on conflict (id) do nothing;

insert into sell_offers(
  id,seller_profile_id,commodity_id,grade_id,origin_location_id,quantity_kg,remaining_quantity_kg,
  minimum_price_bdt_per_kg,available_from,available_until,fulfilment_preference,status
)
select '50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',c.id,'40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',120000,120000,29.20,current_date,current_date+2,'collection_base','open'
from commodities c where c.code='POTATO'
on conflict (id) do nothing;

insert into sell_offers(
  id,seller_profile_id,commodity_id,grade_id,origin_location_id,quantity_kg,remaining_quantity_kg,
  minimum_price_bdt_per_kg,available_from,available_until,fulfilment_preference,status
)
select '50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002',c.id,'40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',65000,65000,46.50,current_date,current_date+2,'collection_base','open'
from commodities c where c.code='ONION'
on conflict (id) do nothing;

insert into sell_offers(
  id,seller_profile_id,commodity_id,grade_id,origin_location_id,quantity_kg,remaining_quantity_kg,
  minimum_price_bdt_per_kg,available_from,available_until,fulfilment_preference,status
)
select '50000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000003',c.id,'40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002',198000,198000,54.80,current_date,current_date+3,'collection_base','open'
from commodities c where c.code='RICE'
on conflict (id) do nothing;

insert into buy_orders(
  id,buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,
  quantity_kg,remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
)
select '60000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000010',c.id,'40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000010',150000,150000,37.50,current_date+1,current_date+2,'open'
from commodities c where c.code='POTATO'
on conflict (id) do nothing;

insert into buy_orders(
  id,buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,
  quantity_kg,remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
)
select '60000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000011',c.id,'40000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000010',135000,135000,55.00,current_date+1,current_date+3,'open'
from commodities c where c.code='ONION'
on conflict (id) do nothing;

insert into buy_orders(
  id,buyer_organization_id,created_by_profile_id,commodity_id,grade_id,destination_location_id,
  quantity_kg,remaining_quantity_kg,target_price_bdt_per_kg,delivery_from,delivery_until,status
)
select '60000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000012',c.id,'40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000010',95000,95000,60.00,current_date+2,current_date+4,'open'
from commodities c where c.code='RICE'
on conflict (id) do nothing;

insert into market_observations(commodity_id,grade_id,location_id,observed_at,observation_type,price_bdt_per_kg,quantity_kg,source_type,source_reference,verified,provenance)
select c.id,'40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',now(),'indicative_farmgate',29.20,120000,'prototype_seed','v0.4 simulated pilot seed',false,'{"simulated":true}'::jsonb
from commodities c where c.code='POTATO';
