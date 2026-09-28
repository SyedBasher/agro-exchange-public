-- Agro-Exchange v1.10 real-JWT pilot account readiness
-- READ ONLY. Run against staging to determine whether independent role accounts
-- exist before any role promotion or bootstrap action.
-- Do not add emails, phone numbers, auth tokens, or participant identities here.

with linked as (
  select
    p.id as profile_id,
    p.role::text as role,
    p.verified,
    (p.auth_user_id is not null) as auth_linked
  from public.profiles p
),
counts as (
  select
    (select count(*) from auth.users) as auth_users,
    count(*) filter (where auth_linked) as linked_profiles,
    count(*) filter (where auth_linked and role='farmer') as linked_farmers,
    count(*) filter (where auth_linked and role='buyer') as linked_buyers,
    count(*) filter (where auth_linked and role='qc_operator') as linked_qc_operators,
    count(*) filter (where auth_linked and role='field_agent') as linked_field_agents,
    count(*) filter (where auth_linked and role='transporter') as linked_transporters,
    count(*) filter (where auth_linked and role='admin') as linked_admins,
    count(*) filter (where auth_linked and role='farmer' and verified) as verified_linked_farmers,
    count(*) filter (where auth_linked and role='buyer' and verified) as verified_linked_buyers
  from linked
)
select
  *,
  (linked_farmers >= 1) as farmer_jwt_ready,
  (linked_buyers >= 1) as buyer_jwt_ready,
  (linked_admins >= 1) as admin_jwt_ready,
  (linked_qc_operators >= 1) as qc_jwt_ready,
  (linked_field_agents >= 1) as field_agent_jwt_ready,
  (linked_transporters >= 1) as transporter_jwt_ready,
  (auth_users >= 3 and linked_farmers >= 1 and linked_admins >= 1 and linked_buyers >= 1)
    as core_farmer_buyer_admin_ready
from counts;
