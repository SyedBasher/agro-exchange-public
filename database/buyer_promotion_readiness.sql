-- Agro-Exchange v1.10 buyer-promotion readiness preflight
-- READ ONLY. Determines whether staging has the minimum independent identities
-- and verified organization coverage needed before promoting a real Auth-linked
-- profile to buyer through the normal admin workflow.

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
    count(*) filter(where role='admin') as linked_admins,
    count(*) filter(where role='farmer') as linked_farmers,
    count(*) filter(where role='buyer') as linked_buyers,
    count(*) as linked_profiles
  from linked
),
candidates as (
  select l.profile_id,l.role,l.verified
  from linked l
  where l.role='farmer'
    and coalesce(l.verified,false)=false
    and not exists (
      select 1 from linked a
      where a.profile_id=l.profile_id and a.role='admin'
    )
),
orgs as (
  select count(*) filter(where verified=true) as verified_orgs
  from public.buyer_organizations
)
select
  s.linked_profiles,
  s.linked_admins,
  s.linked_farmers,
  s.linked_buyers,
  o.verified_orgs,
  count(c.profile_id) as unverified_linked_farmer_candidates,
  (
    s.linked_admins >= 1
    and o.verified_orgs >= 1
    and count(c.profile_id) >= 1
  ) as buyer_promotion_ready
from summary s
cross join orgs o
left join candidates c on true
group by s.linked_profiles,s.linked_admins,s.linked_farmers,s.linked_buyers,o.verified_orgs;
