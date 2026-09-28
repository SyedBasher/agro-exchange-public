-- Agro-Exchange v1.10 first-admin eligibility preflight
-- READ ONLY. This query does not reveal email, phone, token, or raw auth metadata.
-- Run only in staging before the one-time bootstrap_first_admin(...) call.

with linked as (
  select
    p.id as profile_id,
    p.auth_user_id,
    p.role::text as role,
    p.verified,
    p.created_at
  from public.profiles p
  where p.auth_user_id is not null
),
summary as (
  select
    (select count(*) from auth.users) as auth_users,
    count(*) as linked_profiles,
    count(*) filter (where role='admin') as linked_admins
  from linked
),
candidates as (
  select
    l.profile_id,
    l.auth_user_id,
    l.role,
    l.verified,
    row_number() over (order by l.created_at asc, l.profile_id) as linked_sequence
  from linked l
  where l.role='farmer'
)
select
  s.auth_users,
  s.linked_profiles,
  s.linked_admins,
  count(c.profile_id) filter (where c.linked_sequence >= 2) as non_original_farmer_candidates,
  (
    s.auth_users >= 2
    and s.linked_profiles >= 2
    and s.linked_admins = 0
    and count(c.profile_id) filter (where c.linked_sequence >= 2) >= 1
  ) as first_admin_bootstrap_ready
from summary s
cross join candidates c
group by s.auth_users,s.linked_profiles,s.linked_admins;
