-- Agro-Exchange v1.4 hardening
-- 1) unverified profiles cannot retain privileged roles through the admin console
-- 2) notification outbox receives the `confirmed` event before the no-QC routing event

create or replace function public.admin_update_profile_access(
  p_profile_id uuid,
  p_verified boolean,
  p_role text,
  p_buyer_organization_id uuid default null,
  p_note text default null
)
returns table(profile_id uuid, role text, verified boolean, buyer_organization_id uuid)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_admin public.profiles%rowtype;
  v_target public.profiles%rowtype;
  v_role public.user_role;
  v_org public.buyer_organizations%rowtype;
begin
  v_admin:=public.require_admin_profile();
  if p_profile_id=v_admin.id then raise exception 'An admin cannot change their own access through this workflow'; end if;
  select * into v_target from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'Profile not found'; end if;
  begin
    v_role:=p_role::public.user_role;
  exception when invalid_text_representation then
    raise exception 'Invalid role';
  end;

  if not coalesce(p_verified,false) and v_role<>'farmer' then
    raise exception 'An unverified profile cannot hold a privileged role';
  end if;

  if v_role='buyer' then
    if p_buyer_organization_id is null then raise exception 'Buyer organization is required for buyer role'; end if;
    select * into v_org from public.buyer_organizations where id=p_buyer_organization_id;
    if not found then raise exception 'Buyer organization not found'; end if;
    if not v_org.verified then raise exception 'Buyer organization must be verified before approving a buyer'; end if;
  end if;

  update public.profiles
  set role=v_role,verified=coalesce(p_verified,false),updated_at=now()
  where id=p_profile_id;

  if v_role='buyer' and p_buyer_organization_id is not null then
    insert into public.buyer_memberships(buyer_organization_id,profile_id)
    values(p_buyer_organization_id,p_profile_id)
    on conflict do nothing;
  end if;

  insert into public.admin_audit_log(actor_profile_id,action,target_type,target_id,details)
  values(v_admin.id,'profile_access_updated','profile',p_profile_id,
    jsonb_build_object('old_role',v_target.role::text,'new_role',v_role::text,'old_verified',v_target.verified,
      'new_verified',coalesce(p_verified,false),'buyer_organization_id',p_buyer_organization_id,'note',nullif(trim(coalesce(p_note,'')),'')));

  return query select p_profile_id,v_role::text,coalesce(p_verified,false),p_buyer_organization_id;
end;
$$;

-- PostgreSQL fires same-kind triggers in name order. Queue the original event first,
-- then route no-QC trades and generate the later ready_for_dispatch event.
drop trigger if exists trade_status_event_notification_outbox on public.trade_status_events;
drop trigger if exists route_no_qc_after_confirmation_event on public.trade_status_events;
drop trigger if exists a_trade_status_event_notification_outbox on public.trade_status_events;
drop trigger if exists z_route_no_qc_after_confirmation_event on public.trade_status_events;

create trigger a_trade_status_event_notification_outbox
after insert on public.trade_status_events
for each row execute function public.queue_trade_status_notifications();

create trigger z_route_no_qc_after_confirmation_event
after insert on public.trade_status_events
for each row when (new.status='confirmed')
execute function public.route_trade_when_qc_not_required();

revoke all on function public.admin_update_profile_access(uuid,boolean,text,uuid,text) from public,anon;
grant execute on function public.admin_update_profile_access(uuid,boolean,text,uuid,text) to authenticated;
