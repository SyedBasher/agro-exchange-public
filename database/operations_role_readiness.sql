-- Agro-Exchange v1.10 operational-role readiness
-- READ ONLY. Seeded/unlinked profiles never satisfy JWT readiness.

with linked as (
  select
    p.id,
    p.role::text as role,
    p.verified,
    row_number() over(order by p.created_at asc,p.id asc) as linked_sequence
  from public.profiles p
  where p.auth_user_id is not null
)
select
  count(*) filter(where role='admin') as linked_admins,
  count(*) filter(where role='qc_operator' and verified) as verified_linked_qc_operators,
  count(*) filter(where role='field_agent' and verified) as verified_linked_field_agents,
  count(*) filter(where role='transporter' and verified) as verified_linked_transporters,
  count(*) filter(where role='farmer' and linked_sequence>=2 and not verified) as promotable_non_original_farmers,
  (
    count(*) filter(where role='admin') >= 1
    and count(*) filter(where role='qc_operator' and verified) >= 1
    and count(*) filter(where role='field_agent' and verified) >= 1
    and count(*) filter(where role='transporter' and verified) >= 1
  ) as operations_jwt_ready
from linked;
