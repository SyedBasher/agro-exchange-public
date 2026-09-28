-- Agro-Exchange v1.10 dispute-entry continuity.
-- Historical buyer-party identity may continue resolving an existing trade
-- even if current verification/membership is later revoked.

create or replace function public.open_trade_dispute(
  p_trade_id uuid,p_dispute_type text,p_summary text,
  p_details text default null,p_evidence_objects jsonb default '[]'::jsonb
)
returns table(dispute_id uuid,dispute_status text,trade_status text,resume_trade_status text)
language plpgsql security definer set search_path=public as $$
declare
  v_profile public.profiles%rowtype;v_trade public.trades%rowtype;
  v_allowed boolean:=false;v_resume public.trade_status;v_event_type text;
  v_dispute_id uuid;v_evidence jsonb:=coalesce(p_evidence_objects,'[]'::jsonb);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  select * into v_trade from public.trades where id=p_trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_allowed:=v_trade.seller_profile_id=v_profile.id
    or public.is_trade_buyer_party(v_trade.id,v_profile.id)
    or v_profile.role='admin';
  if not v_allowed then raise exception 'Trade participant or admin access required'; end if;

  if v_trade.status in ('settled','cancelled') then
    raise exception 'A settled or cancelled trade cannot open a new dispute';
  end if;
  if p_dispute_type not in ('quantity_shortfall','grade_mismatch','damage_condition','delivery_rejection','payment_issue','other') then
    raise exception 'Unsupported dispute type';
  end if;
  if char_length(btrim(coalesce(p_summary,'')))<3 then raise exception 'Dispute summary is required'; end if;
  if jsonb_typeof(v_evidence)<>'array' or jsonb_array_length(v_evidence)>4 then
    raise exception 'Evidence must be an array with at most four objects';
  end if;
  if exists(select 1 from public.trade_disputes d where d.trade_id=p_trade_id and d.status in ('open','proposal_pending')) then
    raise exception 'An active dispute already exists for this trade';
  end if;

  if v_trade.status='disputed' then
    select e.metadata->>'event_type' into v_event_type
    from public.trade_status_events e
    where e.trade_id=v_trade.id and e.status='disputed'
    order by e.created_at desc,e.id desc limit 1;

    if v_event_type='buyer_receipt_disputed' then
      v_resume:='delivered'::public.trade_status;
    elsif v_event_type in ('qc_rejected','qc_failed') then
      v_resume:='ready_for_dispatch'::public.trade_status;
    else
      raise exception 'Cannot determine a safe resume state for this disputed trade';
    end if;
  else
    v_resume:=v_trade.status;
  end if;

  insert into public.trade_disputes(
    trade_id,opened_by_profile_id,dispute_type,summary,details,evidence_objects,status,resume_trade_status
  ) values(
    v_trade.id,v_profile.id,p_dispute_type,btrim(p_summary),
    nullif(btrim(coalesce(p_details,'')),''),v_evidence,'open',v_resume
  ) returning id into v_dispute_id;

  if v_trade.status<>'disputed' then
    update public.trades set status='disputed',updated_at=now() where id=v_trade.id;
  end if;

  update public.payment_obligations
  set status=case when status='paid' then status else 'disputed' end,updated_at=now()
  where trade_id=v_trade.id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(v_trade.id,'disputed',v_profile.id,jsonb_build_object(
    'event_type','trade_dispute_opened','dispute_id',v_dispute_id,
    'dispute_type',p_dispute_type,'resume_status',v_resume::text
  ));

  return query select v_dispute_id,'open'::text,'disputed'::text,v_resume::text;
end;$$;

create or replace function public.get_dispute_candidates()
returns table(
  trade_id uuid,confirmation_reference text,commodity_code text,commodity_name_en text,
  commodity_name_bn text,grade_code text,origin_district text,destination_district text,
  agreed_quantity_kg numeric,agreed_price_bdt_per_kg numeric,trade_status text,
  active_dispute_id uuid,is_seller boolean,is_buyer boolean
)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  return query
  select
    t.id,tc.reference,c.code,c.name_en,c.name_bn,g.code,lo.district,ld.district,
    t.agreed_quantity_kg,t.agreed_price_bdt_per_kg,t.status::text,d.id,
    (t.seller_profile_id=v_profile.id),
    public.is_trade_buyer_party(t.id,v_profile.id)
  from public.trades t
  join public.commodities c on c.id=t.commodity_id
  left join public.commodity_grades g on g.id=t.grade_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join public.trade_disputes d on d.trade_id=t.id and d.status in ('open','proposal_pending')
  where t.status not in ('settled','cancelled')
    and (
      t.seller_profile_id=v_profile.id
      or public.is_trade_buyer_party(t.id,v_profile.id)
      or v_profile.role='admin'
    )
  order by t.updated_at desc,t.created_at desc;
end;$$;

create or replace function public.get_my_disputes()
returns table(
  dispute_id uuid,trade_id uuid,confirmation_reference text,dispute_type text,
  dispute_summary text,dispute_details text,dispute_status text,resume_trade_status text,
  evidence_objects jsonb,opened_at timestamptz,commodity_code text,commodity_name_en text,
  commodity_name_bn text,grade_code text,origin_district text,destination_district text,
  agreed_quantity_kg numeric,agreed_price_bdt_per_kg numeric,is_seller boolean,is_buyer boolean,
  proposal_id uuid,resolution_type text,proposed_quantity_kg numeric,
  proposed_unit_price_bdt_per_kg numeric,proposed_grade_code text,
  proposed_amount_due_bdt numeric,proposal_rationale text,proposal_status text,
  seller_accepted boolean,buyer_accepted boolean,proposal_created_at timestamptz
)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  return query
  select
    d.id,d.trade_id,tc.reference,d.dispute_type,d.summary,d.details,d.status,
    d.resume_trade_status::text,d.evidence_objects,d.created_at,
    c.code,c.name_en,c.name_bn,g0.code,lo.district,ld.district,
    t.agreed_quantity_kg,t.agreed_price_bdt_per_kg,
    (t.seller_profile_id=v_profile.id),
    public.is_trade_buyer_party(t.id,v_profile.id),
    ap.id,ap.resolution_type,ap.proposed_quantity_kg,ap.proposed_unit_price_bdt_per_kg,
    g1.code,ap.proposed_amount_due_bdt,ap.rationale,ap.status,
    (ap.seller_accepted_at is not null),(ap.buyer_accepted_at is not null),ap.created_at
  from public.trade_disputes d
  join public.trades t on t.id=d.trade_id
  join public.commodities c on c.id=t.commodity_id
  left join public.commodity_grades g0 on g0.id=t.grade_id
  left join public.locations lo on lo.id=t.origin_location_id
  left join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join lateral (
    select p.* from public.trade_adjustment_proposals p
    where p.dispute_id=d.id
    order by (p.status='pending') desc,p.created_at desc
    limit 1
  ) ap on true
  left join public.commodity_grades g1 on g1.id=ap.proposed_grade_id
  where
    t.seller_profile_id=v_profile.id
    or public.is_trade_buyer_party(t.id,v_profile.id)
    or v_profile.role='admin'
  order by (d.status in ('open','proposal_pending')) desc,d.updated_at desc,d.created_at desc;
end;$$;

revoke all on function public.open_trade_dispute(uuid,text,text,text,jsonb) from public,anon;
grant execute on function public.open_trade_dispute(uuid,text,text,text,jsonb) to authenticated;
revoke all on function public.get_dispute_candidates() from public,anon;
grant execute on function public.get_dispute_candidates() to authenticated;
revoke all on function public.get_my_disputes() from public,anon;
grant execute on function public.get_my_disputes() to authenticated;
