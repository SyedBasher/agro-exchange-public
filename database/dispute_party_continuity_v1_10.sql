-- Agro-Exchange v1.10 dispute-party continuity hardening.
-- New trading remains verification-gated. Existing commercial obligations remain
-- resolvable by the historically recorded buyer participant even if current
-- buyer membership is later revoked.

create or replace function public.is_trade_buyer_party(
  p_trade_id uuid,
  p_profile_id uuid
)
returns boolean
language sql
security definer
set search_path=public
as $$
  select exists(
    select 1
    from public.trades t
    where t.id=p_trade_id
      and (
        exists(
          select 1
          from public.trade_confirmations tc
          where tc.trade_id=t.id
            and tc.buyer_accepted_by=p_profile_id
        )
        or exists(
          select 1
          from public.profiles p
          join public.buyer_memberships bm on bm.profile_id=p.id
          join public.buyer_organizations org
            on org.id=bm.buyer_organization_id and org.verified=true
          where p.id=p_profile_id
            and p.role='buyer'
            and p.verified=true
            and bm.buyer_organization_id=t.buyer_organization_id
        )
      )
  );
$$;

revoke all on function public.is_trade_buyer_party(uuid,uuid)
from public,anon,authenticated,service_role;

create or replace function public.propose_trade_adjustment(
  p_dispute_id uuid,
  p_resolution_type text,
  p_quantity_kg numeric default null,
  p_unit_price_bdt_per_kg numeric default null,
  p_grade_code text default null,
  p_rationale text default null
)
returns table(
  proposal_id uuid,proposal_status text,proposed_amount_due_bdt numeric,
  seller_accepted boolean,buyer_accepted boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_dispute public.trade_disputes%rowtype;
  v_trade public.trades%rowtype;
  v_is_seller boolean:=false;
  v_is_buyer boolean:=false;
  v_grade_id uuid;
  v_qty numeric(14,2);
  v_price numeric(12,2);
  v_amount numeric(16,2);
  v_proposal_id uuid;
  v_seller_accepted boolean:=false;
  v_buyer_accepted boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  select * into v_dispute from public.trade_disputes where id=p_dispute_id for update;
  if not found then raise exception 'Dispute not found'; end if;
  if v_dispute.status not in ('open','proposal_pending') then
    raise exception 'Dispute is not open for adjustment proposals';
  end if;

  select * into v_trade from public.trades where id=v_dispute.trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_is_seller:=v_trade.seller_profile_id=v_profile.id;
  v_is_buyer:=public.is_trade_buyer_party(v_trade.id,v_profile.id);

  if not (v_is_seller or v_is_buyer or v_profile.role='admin') then
    raise exception 'Trade participant or admin access required';
  end if;

  if exists(
    select 1 from public.trade_adjustment_proposals p
    where p.dispute_id=v_dispute.id and p.status='pending'
  ) then
    raise exception 'A pending proposal already exists for this dispute';
  end if;

  if p_resolution_type not in (
    'accept_original','revise_terms','partial_rejection','full_rejection','cancel_trade'
  ) then
    raise exception 'Unsupported resolution type';
  end if;

  v_grade_id:=v_trade.grade_id;
  if nullif(btrim(coalesce(p_grade_code,'')),'') is not null then
    select g.id into v_grade_id
    from public.commodity_grades g
    where g.commodity_id=v_trade.commodity_id
      and upper(g.code)=upper(btrim(p_grade_code))
    limit 1;
    if v_grade_id is null then
      raise exception 'Proposed grade is not valid for this commodity';
    end if;
  end if;

  if p_resolution_type='accept_original' then
    v_qty:=v_trade.agreed_quantity_kg;
    v_price:=v_trade.agreed_price_bdt_per_kg;
  elsif p_resolution_type in ('revise_terms','partial_rejection') then
    if p_quantity_kg is null or p_quantity_kg<=0 then
      raise exception 'Proposed quantity must be greater than zero';
    end if;
    if p_unit_price_bdt_per_kg is null or p_unit_price_bdt_per_kg<=0 then
      raise exception 'Proposed unit price must be greater than zero';
    end if;
    if p_resolution_type='partial_rejection'
       and p_quantity_kg>=v_trade.agreed_quantity_kg then
      raise exception 'Partial rejection must reduce the commercial quantity';
    end if;
    v_qty:=round(p_quantity_kg,2);
    v_price:=round(p_unit_price_bdt_per_kg,2);
  else
    v_qty:=null;
    v_price:=null;
    v_grade_id:=null;
  end if;

  v_amount:=case when v_qty is null then 0 else round(v_qty*v_price,2) end;

  insert into public.trade_adjustment_proposals(
    dispute_id,proposed_by_profile_id,resolution_type,proposed_quantity_kg,
    proposed_unit_price_bdt_per_kg,proposed_grade_id,proposed_amount_due_bdt,
    rationale,status,seller_accepted_by,seller_accepted_at,
    buyer_accepted_by,buyer_accepted_at
  ) values(
    v_dispute.id,v_profile.id,p_resolution_type,v_qty,v_price,v_grade_id,v_amount,
    nullif(btrim(coalesce(p_rationale,'')),''),
    'pending',
    case when v_is_seller then v_profile.id else null end,
    case when v_is_seller then now() else null end,
    case when v_is_buyer then v_profile.id else null end,
    case when v_is_buyer then now() else null end
  )
  returning id,(seller_accepted_at is not null),(buyer_accepted_at is not null)
  into v_proposal_id,v_seller_accepted,v_buyer_accepted;

  update public.trade_disputes
  set status='proposal_pending',updated_at=now()
  where id=v_dispute.id;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(
    v_trade.id,'disputed',v_profile.id,
    jsonb_build_object(
      'event_type','adjustment_proposed',
      'dispute_id',v_dispute.id,
      'proposal_id',v_proposal_id,
      'resolution_type',p_resolution_type,
      'proposed_amount_due_bdt',v_amount
    )
  );

  return query
  select v_proposal_id,'pending'::text,v_amount,v_seller_accepted,v_buyer_accepted;
end;
$$;

create or replace function public.respond_trade_adjustment(
  p_proposal_id uuid,
  p_accept boolean,
  p_note text default null
)
returns table(
  proposal_id uuid,proposal_status text,dispute_status text,trade_status text,
  amount_due_bdt numeric,seller_accepted boolean,buyer_accepted boolean
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_proposal public.trade_adjustment_proposals%rowtype;
  v_dispute public.trade_disputes%rowtype;
  v_trade public.trades%rowtype;
  v_is_seller boolean:=false;
  v_is_buyer boolean:=false;
  v_confirmed numeric(16,2):=0;
  v_initiated integer:=0;
  v_final_amount numeric(16,2);
  v_final_qty numeric(14,2);
  v_final_price numeric(12,2);
  v_final_grade uuid;
  v_obligation public.payment_obligations%rowtype;
  v_has_obligation boolean:=false;
  v_next_status public.trade_status;
  v_obligation_status text;
  v_seller_ok boolean;
  v_buyer_ok boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;

  select * into v_proposal
  from public.trade_adjustment_proposals
  where id=p_proposal_id
  for update;
  if not found then raise exception 'Proposal not found'; end if;
  if v_proposal.status<>'pending' then raise exception 'Proposal is no longer pending'; end if;

  select * into v_dispute from public.trade_disputes where id=v_proposal.dispute_id for update;
  if not found then raise exception 'Dispute not found'; end if;
  if v_dispute.status<>'proposal_pending' then
    raise exception 'Dispute is not awaiting commercial-party acceptance';
  end if;

  select * into v_trade from public.trades where id=v_dispute.trade_id for update;
  if not found then raise exception 'Trade not found'; end if;

  v_is_seller:=v_trade.seller_profile_id=v_profile.id;
  v_is_buyer:=public.is_trade_buyer_party(v_trade.id,v_profile.id);

  if not (v_is_seller or v_is_buyer) then
    if v_profile.role='admin' then
      raise exception 'Commercial party acceptance is required; admin cannot substitute for seller or buyer';
    end if;
    raise exception 'Trade participant access required';
  end if;

  if not coalesce(p_accept,false) then
    update public.trade_adjustment_proposals
    set status='rejected',
        rejected_by_profile_id=v_profile.id,
        rejection_note=nullif(btrim(coalesce(p_note,'')),''),
        updated_at=now()
    where id=v_proposal.id;

    update public.trade_disputes
    set status='open',updated_at=now()
    where id=v_dispute.id;

    insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
    values(
      v_trade.id,'disputed',v_profile.id,
      jsonb_build_object(
        'event_type','adjustment_rejected',
        'dispute_id',v_dispute.id,
        'proposal_id',v_proposal.id
      )
    );

    return query
    select v_proposal.id,'rejected'::text,'open'::text,'disputed'::text,
           v_proposal.proposed_amount_due_bdt,
           (v_proposal.seller_accepted_at is not null),
           (v_proposal.buyer_accepted_at is not null);
    return;
  end if;

  if v_is_seller and v_proposal.seller_accepted_at is null then
    update public.trade_adjustment_proposals
    set seller_accepted_by=v_profile.id,seller_accepted_at=now(),updated_at=now()
    where id=v_proposal.id;
  end if;

  if v_is_buyer and v_proposal.buyer_accepted_at is null then
    update public.trade_adjustment_proposals
    set buyer_accepted_by=v_profile.id,buyer_accepted_at=now(),updated_at=now()
    where id=v_proposal.id;
  end if;

  select * into v_proposal
  from public.trade_adjustment_proposals
  where id=p_proposal_id
  for update;

  v_seller_ok:=v_proposal.seller_accepted_at is not null;
  v_buyer_ok:=v_proposal.buyer_accepted_at is not null;

  if not (v_seller_ok and v_buyer_ok) then
    return query
    select v_proposal.id,'pending'::text,'proposal_pending'::text,'disputed'::text,
           v_proposal.proposed_amount_due_bdt,v_seller_ok,v_buyer_ok;
    return;
  end if;

  select count(*) into v_initiated
  from public.payments p
  where p.trade_id=v_trade.id and p.status='initiated';

  if v_initiated>0 then
    raise exception 'An initiated payment must be confirmed or marked failed before the adjustment can be finalized';
  end if;

  select coalesce(sum(p.amount_bdt),0) into v_confirmed
  from public.payments p
  where p.trade_id=v_trade.id and p.status='confirmed';

  v_final_amount:=coalesce(v_proposal.proposed_amount_due_bdt,0);

  if v_confirmed>v_final_amount+0.01 then
    raise exception 'Confirmed payments exceed the proposed amount. Refund/credit handling is required before this adjustment can be finalized';
  end if;

  if v_proposal.resolution_type in ('full_rejection','cancel_trade') then
    if v_confirmed>0.01 then
      raise exception 'A zero-value cancellation cannot be finalized after confirmed payment without refund handling';
    end if;
    v_next_status:='cancelled'::public.trade_status;
    update public.payment_obligations
    set amount_due_bdt=0,status='cancelled',updated_at=now()
    where trade_id=v_trade.id;
  else
    v_final_qty:=coalesce(v_proposal.proposed_quantity_kg,v_trade.agreed_quantity_kg);
    v_final_price:=coalesce(v_proposal.proposed_unit_price_bdt_per_kg,v_trade.agreed_price_bdt_per_kg);
    v_final_grade:=coalesce(v_proposal.proposed_grade_id,v_trade.grade_id);
    v_final_amount:=round(v_final_qty*v_final_price,2);

    select * into v_obligation
    from public.payment_obligations
    where trade_id=v_trade.id
    for update;
    v_has_obligation:=found;

    if v_has_obligation then
      v_obligation_status:=case
        when v_final_amount<=v_confirmed+0.01 then 'paid'
        when v_confirmed>0 then 'partially_paid'
        else 'due'
      end;

      update public.payment_obligations
      set basis_quantity_kg=v_final_qty,
          unit_price_bdt_per_kg=v_final_price,
          amount_due_bdt=v_final_amount,
          status=v_obligation_status,
          due_at=case
            when v_obligation_status='paid' then due_at
            else coalesce(due_at,now())
          end,
          updated_at=now()
      where trade_id=v_trade.id;
    end if;

    if v_has_obligation and v_final_amount<=v_confirmed+0.01 then
      v_next_status:='settled'::public.trade_status;
    else
      v_next_status:=v_dispute.resume_trade_status;
      if v_next_status='disputed' then
        raise exception 'Resolved dispute has no safe resume state';
      end if;
    end if;
  end if;

  update public.trade_adjustment_proposals
  set status='accepted',
      applied_at=now(),
      updated_at=now(),
      proposed_amount_due_bdt=v_final_amount
  where id=v_proposal.id;

  update public.trade_disputes
  set status='resolved',
      resolution_type=v_proposal.resolution_type,
      resolved_at=now(),
      updated_at=now()
  where id=v_dispute.id;

  update public.trades
  set status=v_next_status,
      settled_at=case
        when v_next_status='settled' then coalesce(settled_at,now())
        else settled_at
      end,
      updated_at=now()
  where id=v_trade.id;

  if v_next_status='cancelled' then
    perform public.restore_trade_inventory_after_cancel(v_trade.id);
  end if;

  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata)
  values(
    v_trade.id,v_next_status,v_profile.id,
    jsonb_build_object(
      'event_type','trade_adjustment_applied',
      'dispute_id',v_dispute.id,
      'proposal_id',v_proposal.id,
      'resolution_type',v_proposal.resolution_type,
      'effective_quantity_kg',v_final_qty,
      'effective_unit_price_bdt_per_kg',v_final_price,
      'effective_grade_id',v_final_grade,
      'amount_due_bdt',v_final_amount,
      'confirmed_payments_bdt',v_confirmed
    )
  );

  return query
  select v_proposal.id,'accepted'::text,'resolved'::text,
         v_next_status::text,v_final_amount,true,true;
end;
$$;

revoke all on function public.propose_trade_adjustment(uuid,text,numeric,numeric,text,text)
from public,anon;
grant execute on function public.propose_trade_adjustment(uuid,text,numeric,numeric,text,text)
to authenticated;

revoke all on function public.respond_trade_adjustment(uuid,boolean,text)
from public,anon;
grant execute on function public.respond_trade_adjustment(uuid,boolean,text)
to authenticated;
