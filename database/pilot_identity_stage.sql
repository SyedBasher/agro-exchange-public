-- Agro-Exchange v1.10 pilot identity-stage diagnostic
-- READ ONLY. No email, phone, token, magic link or raw auth metadata is returned.

with linked as (
  select
    p.id as profile_id,
    p.role::text as role,
    p.verified,
    p.created_at,
    row_number() over(order by p.created_at asc,p.id asc) as linked_sequence
  from public.profiles p
  where p.auth_user_id is not null
),
counts as (
  select
    (select count(*) from auth.users) as auth_users,
    count(*) as linked_profiles,
    count(*) filter(where role='farmer') as linked_farmers,
    count(*) filter(where role='admin') as linked_admins,
    count(*) filter(where role='buyer') as linked_buyers,
    count(*) filter(where role='qc_operator') as linked_qc_operators,
    count(*) filter(where role='field_agent') as linked_field_agents,
    count(*) filter(where role='transporter') as linked_transporters,
    count(*) filter(
      where role='farmer'
        and verified=false
        and linked_sequence>=2
    ) as non_original_unverified_farmer_candidates
  from linked
)
select
  auth_users,
  linked_profiles,
  linked_farmers,
  linked_admins,
  linked_buyers,
  linked_qc_operators,
  linked_field_agents,
  linked_transporters,
  non_original_unverified_farmer_candidates,
  case
    when auth_users<2 or linked_profiles<2 then 'WAITING_FOR_SECOND_AUTH_IDENTITY'
    when linked_admins=0 and non_original_unverified_farmer_candidates>=1 then 'FIRST_ADMIN_CANDIDATE_READY'
    when linked_admins>=1 and linked_buyers=0 and non_original_unverified_farmer_candidates>=1 then 'BUYER_CANDIDATE_READY'
    when linked_admins>=1 and linked_buyers>=1
         and (linked_qc_operators=0 or linked_field_agents=0 or linked_transporters=0)
      then 'CORE_TRADING_READY_OPERATIONS_PENDING'
    when linked_admins>=1 and linked_buyers>=1
         and linked_qc_operators>=1 and linked_field_agents>=1 and linked_transporters>=1
      then 'FULL_ROLE_MATRIX_READY'
    else 'REVIEW_REQUIRED'
  end as pilot_identity_stage
from counts;
