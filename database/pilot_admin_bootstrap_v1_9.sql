-- Agro-Exchange v1.9 — controlled first-admin bootstrap.
-- This helper is intentionally NOT executable by browser roles or service_role.
-- It is for a one-time, explicit SQL-editor action after a designated Auth user exists.

create or replace function public.bootstrap_first_admin(p_auth_user_id uuid)
returns table(profile_id uuid,role text,verified boolean)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_original_profile_id uuid;
  v_auth_users bigint;
  v_linked_profiles bigint;
begin
  -- Serialize this one-time bootstrap decision so concurrent attempts cannot race.
  perform pg_advisory_xact_lock(hashtext('agro_exchange_first_admin_bootstrap'));

  if exists(select 1 from public.profiles p where p.role='admin') then
    raise exception 'An admin already exists; use the normal admin access workflow';
  end if;

  select count(*) into v_auth_users from auth.users;
  select count(*) into v_linked_profiles
  from public.profiles
  where auth_user_id is not null;

  if v_auth_users < 2 or v_linked_profiles < 2 then
    raise exception 'A separate second Auth-linked account is required before first-admin bootstrap';
  end if;

  select * into v_profile
  from public.profiles
  where auth_user_id=p_auth_user_id
  for update;

  if not found then
    raise exception 'No Agro-Exchange profile is linked to that Auth user';
  end if;

  select p.id into v_original_profile_id
  from public.profiles p
  where p.auth_user_id is not null
  order by p.created_at asc,p.id asc
  limit 1;

  if v_profile.id=v_original_profile_id then
    raise exception 'The original linked farmer cannot be used for first-admin bootstrap';
  end if;

  if v_profile.role<>'farmer' or coalesce(v_profile.verified,false) then
    raise exception 'First-admin candidate must be a newly linked unverified farmer profile';
  end if;

  update public.profiles
  set role='admin',verified=true,updated_at=now()
  where id=v_profile.id;

  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(
    v_profile.id,'first_admin_bootstrapped','profile',v_profile.id,
    jsonb_build_object('method','controlled_sql_bootstrap','auth_user_id',p_auth_user_id)
  );

  return query select v_profile.id,'admin'::text,true;
end;
$$;

revoke all on function public.bootstrap_first_admin(uuid)
from public,anon,authenticated,service_role;
