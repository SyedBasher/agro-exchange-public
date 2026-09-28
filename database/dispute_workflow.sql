-- Agro-Exchange v1.3: disputes, cancellation and negotiated commercial adjustments
-- Original trade terms remain immutable. Accepted adjustments create an auditable settlement basis.

create table if not exists public.trade_disputes (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references public.trades(id) on delete cascade,
  opened_by_profile_id uuid not null references public.profiles(id),
  dispute_type text not null check (dispute_type in (
    'quantity_shortfall','grade_mismatch','damage_condition','delivery_rejection','payment_issue','other'
  )),
  summary text not null check (char_length(btrim(summary)) between 3 and 180),
  details text,
  evidence_objects jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in ('open','proposal_pending','resolved','cancelled')),
  resume_trade_status public.trade_status not null,
  resolution_type text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trade_disputes_evidence_array check (jsonb_typeof(evidence_objects)='array')
);

create table if not exists public.trade_adjustment_proposals (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.trade_disputes(id) on delete cascade,
  proposed_by_profile_id uuid not null references public.profiles(id),
  resolution_type text not null check (resolution_type in (
    'accept_original','revise_terms','partial_rejection','full_rejection','cancel_trade'
  )),
  proposed_quantity_kg numeric(14,2) check (proposed_quantity_kg is null or proposed_quantity_kg > 0),
  proposed_unit_price_bdt_per_kg numeric(12,2) check (proposed_unit_price_bdt_per_kg is null or proposed_unit_price_bdt_per_kg >= 0),
  proposed_grade_id uuid references public.commodity_grades(id),
  proposed_amount_due_bdt numeric(16,2) check (proposed_amount_due_bdt is null or proposed_amount_due_bdt >= 0),
  rationale text,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','superseded')),
  seller_accepted_by uuid references public.profiles(id),
  seller_accepted_at timestamptz,
  buyer_accepted_by uuid references public.profiles(id),
  buyer_accepted_at timestamptz,
  rejected_by_profile_id uuid references public.profiles(id),
  rejection_note text,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists trade_disputes_one_active_per_trade_idx on public.trade_disputes(trade_id) where status in ('open','proposal_pending');
create unique index if not exists trade_adjustment_one_pending_per_dispute_idx on public.trade_adjustment_proposals(dispute_id) where status='pending';
create index if not exists trade_disputes_trade_status_idx on public.trade_disputes(trade_id,status,created_at desc);
create index if not exists trade_disputes_opened_by_idx on public.trade_disputes(opened_by_profile_id,created_at desc);
create index if not exists adjustment_proposals_dispute_idx on public.trade_adjustment_proposals(dispute_id,created_at desc);
create index if not exists adjustment_proposals_proposed_by_idx on public.trade_adjustment_proposals(proposed_by_profile_id,created_at desc);

alter table public.trade_disputes enable row level security;
alter table public.trade_adjustment_proposals enable row level security;

drop policy if exists trade_disputes_participant_read on public.trade_disputes;
create policy trade_disputes_participant_read on public.trade_disputes for select to authenticated using (
  exists (
    select 1 from public.trades t where t.id=trade_disputes.trade_id and (
      t.seller_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
      or exists (select 1 from public.buyer_memberships bm join public.profiles p on p.id=bm.profile_id where p.auth_user_id=(select auth.uid()) and bm.buyer_organization_id=t.buyer_organization_id)
      or exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
    )
  )
);

drop policy if exists adjustment_proposals_participant_read on public.trade_adjustment_proposals;
create policy adjustment_proposals_participant_read on public.trade_adjustment_proposals for select to authenticated using (
  exists (
    select 1 from public.trade_disputes d join public.trades t on t.id=d.trade_id where d.id=trade_adjustment_proposals.dispute_id and (
      t.seller_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
      or exists (select 1 from public.buyer_memberships bm join public.profiles p on p.id=bm.profile_id where p.auth_user_id=(select auth.uid()) and bm.buyer_organization_id=t.buyer_organization_id)
      or exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
    )
  )
);

revoke insert,update,delete on public.trade_disputes from anon,authenticated;
revoke insert,update,delete on public.trade_adjustment_proposals from anon,authenticated;
grant select on public.trade_disputes,public.trade_adjustment_proposals to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('dispute-evidence','dispute-evidence',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists dispute_evidence_insert_participant on storage.objects;
create policy dispute_evidence_insert_participant on storage.objects for insert to authenticated with check (
  bucket_id='dispute-evidence' and exists (
    select 1 from public.trades t where t.id::text=split_part(storage.objects.name,'/',1) and (
      t.seller_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
      or exists (select 1 from public.buyer_memberships bm join public.profiles p on p.id=bm.profile_id where p.auth_user_id=(select auth.uid()) and bm.buyer_organization_id=t.buyer_organization_id)
      or exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
    )
  )
);

drop policy if exists dispute_evidence_select_participant on storage.objects;
create policy dispute_evidence_select_participant on storage.objects for select to authenticated using (
  bucket_id='dispute-evidence' and exists (
    select 1 from public.trades t where t.id::text=split_part(storage.objects.name,'/',1) and (
      t.seller_profile_id=(select p.id from public.profiles p where p.auth_user_id=(select auth.uid()) limit 1)
      or exists (select 1 from public.buyer_memberships bm join public.profiles p on p.id=bm.profile_id where p.auth_user_id=(select auth.uid()) and bm.buyer_organization_id=t.buyer_organization_id)
      or exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
    )
  )
);

drop policy if exists dispute_evidence_delete_admin on storage.objects;
create policy dispute_evidence_delete_admin on storage.objects for delete to authenticated using (
  bucket_id='dispute-evidence' and exists (select 1 from public.profiles p where p.auth_user_id=(select auth.uid()) and p.role='admin')
);

alter table public.payment_obligations drop constraint if exists payment_obligations_status_check;
alter table public.payment_obligations add constraint payment_obligations_status_check check (status in ('pending_receipt','due','initiated','partially_paid','paid','disputed','cancelled'));

create or replace function public.get_dispute_candidates()
returns table(trade_id uuid,confirmation_reference text,commodity_code text,commodity_name_en text,commodity_name_bn text,grade_code text,origin_district text,destination_district text,agreed_quantity_kg numeric,agreed_price_bdt_per_kg numeric,trade_status text,active_dispute_id uuid,is_seller boolean,is_buyer boolean)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  return query
  select t.id,tc.reference,c.code,c.name_en,c.name_bn,g.code,lo.district,ld.district,t.agreed_quantity_kg,t.agreed_price_bdt_per_kg,t.status::text,d.id,
    (t.seller_profile_id=v_profile.id),exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id)
  from public.trades t
  join public.commodities c on c.id=t.commodity_id
  left join public.commodity_grades g on g.id=t.grade_id
  join public.locations lo on lo.id=t.origin_location_id
  join public.locations ld on ld.id=t.destination_location_id
  left join public.trade_confirmations tc on tc.trade_id=t.id
  left join public.trade_disputes d on d.trade_id=t.id and d.status in ('open','proposal_pending')
  where t.status not in ('settled','cancelled') and (
    t.seller_profile_id=v_profile.id
    or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id)
    or v_profile.role='admin'
  ) order by t.updated_at desc,t.created_at desc;
end;$$;

create or replace function public.get_my_disputes()
returns table(dispute_id uuid,trade_id uuid,confirmation_reference text,dispute_type text,dispute_summary text,dispute_details text,dispute_status text,resume_trade_status text,evidence_objects jsonb,opened_at timestamptz,commodity_code text,commodity_name_en text,commodity_name_bn text,grade_code text,origin_district text,destination_district text,agreed_quantity_kg numeric,agreed_price_bdt_per_kg numeric,is_seller boolean,is_buyer boolean,proposal_id uuid,resolution_type text,proposed_quantity_kg numeric,proposed_unit_price_bdt_per_kg numeric,proposed_grade_code text,proposed_amount_due_bdt numeric,proposal_rationale text,proposal_status text,seller_accepted boolean,buyer_accepted boolean,proposal_created_at timestamptz)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;
  if not found then raise exception 'Profile not found'; end if;
  return query
  select d.id,d.trade_id,tc.reference,d.dispute_type,d.summary,d.details,d.status,d.resume_trade_status::text,d.evidence_objects,d.created_at,
    c.code,c.name_en,c.name_bn,g0.code,lo.district,ld.district,t.agreed_quantity_kg,t.agreed_price_bdt_per_kg,
    (t.seller_profile_id=v_profile.id),exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id),
    ap.id,ap.resolution_type,ap.proposed_quantity_kg,ap.proposed_unit_price_bdt_per_kg,g1.code,ap.proposed_amount_due_bdt,ap.rationale,ap.status,
    (ap.seller_accepted_at is not null),(ap.buyer_accepted_at is not null),ap.created_at
  from public.trade_disputes d join public.trades t on t.id=d.trade_id join public.commodities c on c.id=t.commodity_id
  left join public.commodity_grades g0 on g0.id=t.grade_id left join public.locations lo on lo.id=t.origin_location_id left join public.locations ld on ld.id=t.destination_location_id left join public.trade_confirmations tc on tc.trade_id=t.id
  left join lateral (select p.* from public.trade_adjustment_proposals p where p.dispute_id=d.id order by (p.status='pending') desc,p.created_at desc limit 1) ap on true
  left join public.commodity_grades g1 on g1.id=ap.proposed_grade_id
  where t.seller_profile_id=v_profile.id or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=t.buyer_organization_id) or v_profile.role='admin'
  order by (d.status in ('open','proposal_pending')) desc,d.updated_at desc,d.created_at desc;
end;$$;

create or replace function public.open_trade_dispute(p_trade_id uuid,p_dispute_type text,p_summary text,p_details text default null,p_evidence_objects jsonb default '[]'::jsonb)
returns table(dispute_id uuid,dispute_status text,trade_status text,resume_trade_status text)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;v_trade public.trades%rowtype;v_allowed boolean:=false;v_resume public.trade_status;v_event_type text;v_dispute_id uuid;v_evidence jsonb:=coalesce(p_evidence_objects,'[]'::jsonb);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;if not found then raise exception 'Profile not found'; end if;
  select * into v_trade from public.trades where id=p_trade_id for update;if not found then raise exception 'Trade not found'; end if;
  v_allowed:=v_trade.seller_profile_id=v_profile.id or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id) or v_profile.role='admin';
  if not v_allowed then raise exception 'Trade participant or admin access required'; end if;
  if v_trade.status in ('settled','cancelled') then raise exception 'A settled or cancelled trade cannot open a new dispute'; end if;
  if p_dispute_type not in ('quantity_shortfall','grade_mismatch','damage_condition','delivery_rejection','payment_issue','other') then raise exception 'Unsupported dispute type'; end if;
  if char_length(btrim(coalesce(p_summary,'')))<3 then raise exception 'Dispute summary is required'; end if;
  if jsonb_typeof(v_evidence)<>'array' or jsonb_array_length(v_evidence)>4 then raise exception 'Evidence must be an array with at most four objects'; end if;
  if exists(select 1 from public.trade_disputes d where d.trade_id=p_trade_id and d.status in ('open','proposal_pending')) then raise exception 'An active dispute already exists for this trade'; end if;
  if v_trade.status='disputed' then
    select e.metadata->>'event_type' into v_event_type from public.trade_status_events e where e.trade_id=v_trade.id and e.status='disputed' order by e.created_at desc limit 1;
    v_resume:=case when v_event_type='buyer_receipt_disputed' then 'delivered'::public.trade_status when v_event_type in ('qc_rejected','qc_failed') then 'ready_for_dispatch'::public.trade_status else 'delivered'::public.trade_status end;
  else v_resume:=v_trade.status;end if;
  insert into public.trade_disputes(trade_id,opened_by_profile_id,dispute_type,summary,details,evidence_objects,status,resume_trade_status)
  values(v_trade.id,v_profile.id,p_dispute_type,btrim(p_summary),nullif(btrim(coalesce(p_details,'')),''),v_evidence,'open',v_resume) returning id into v_dispute_id;
  if v_trade.status<>'disputed' then update public.trades set status='disputed',updated_at=now() where id=v_trade.id;end if;
  update public.payment_obligations set status=case when status='paid' then status else 'disputed' end,updated_at=now() where trade_id=v_trade.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'disputed',v_profile.id,jsonb_build_object('event_type','trade_dispute_opened','dispute_id',v_dispute_id,'dispute_type',p_dispute_type,'resume_status',v_resume::text));
  return query select v_dispute_id,'open'::text,'disputed'::text,v_resume::text;
end;$$;

create or replace function public.propose_trade_adjustment(p_dispute_id uuid,p_resolution_type text,p_quantity_kg numeric default null,p_unit_price_bdt_per_kg numeric default null,p_grade_code text default null,p_rationale text default null)
returns table(proposal_id uuid,proposal_status text,proposed_amount_due_bdt numeric,seller_accepted boolean,buyer_accepted boolean)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;v_dispute public.trade_disputes%rowtype;v_trade public.trades%rowtype;v_is_seller boolean:=false;v_is_buyer boolean:=false;v_grade_id uuid;v_qty numeric(14,2);v_price numeric(12,2);v_amount numeric(16,2);v_proposal_id uuid;v_seller_accepted boolean:=false;v_buyer_accepted boolean:=false;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;if not found then raise exception 'Profile not found'; end if;
  select * into v_dispute from public.trade_disputes where id=p_dispute_id for update;if not found then raise exception 'Dispute not found'; end if;if v_dispute.status not in ('open','proposal_pending') then raise exception 'Dispute is not open for adjustment proposals'; end if;
  select * into v_trade from public.trades where id=v_dispute.trade_id for update;if not found then raise exception 'Trade not found'; end if;
  v_is_seller:=v_trade.seller_profile_id=v_profile.id;v_is_buyer:=exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id);
  if not (v_is_seller or v_is_buyer or v_profile.role='admin') then raise exception 'Trade participant or admin access required'; end if;
  if exists(select 1 from public.trade_adjustment_proposals p where p.dispute_id=v_dispute.id and p.status='pending') then raise exception 'A pending proposal already exists for this dispute'; end if;
  if p_resolution_type not in ('accept_original','revise_terms','partial_rejection','full_rejection','cancel_trade') then raise exception 'Unsupported resolution type'; end if;
  v_grade_id:=v_trade.grade_id;if nullif(btrim(coalesce(p_grade_code,'')),'') is not null then select g.id into v_grade_id from public.commodity_grades g where g.commodity_id=v_trade.commodity_id and upper(g.code)=upper(btrim(p_grade_code)) limit 1;if v_grade_id is null then raise exception 'Proposed grade is not valid for this commodity'; end if;end if;
  if p_resolution_type='accept_original' then v_qty:=v_trade.agreed_quantity_kg;v_price:=v_trade.agreed_price_bdt_per_kg;
  elsif p_resolution_type in ('revise_terms','partial_rejection') then if p_quantity_kg is null or p_quantity_kg<=0 then raise exception 'Proposed quantity must be greater than zero'; end if;if p_unit_price_bdt_per_kg is null or p_unit_price_bdt_per_kg<0 then raise exception 'Proposed unit price must be zero or greater'; end if;if p_resolution_type='partial_rejection' and p_quantity_kg>=v_trade.agreed_quantity_kg then raise exception 'Partial rejection must reduce the commercial quantity'; end if;v_qty:=round(p_quantity_kg,2);v_price:=round(p_unit_price_bdt_per_kg,2);
  else v_qty:=null;v_price:=null;v_grade_id:=null;end if;
  v_amount:=case when v_qty is null then 0 else round(v_qty*v_price,2) end;
  insert into public.trade_adjustment_proposals(dispute_id,proposed_by_profile_id,resolution_type,proposed_quantity_kg,proposed_unit_price_bdt_per_kg,proposed_grade_id,proposed_amount_due_bdt,rationale,status,seller_accepted_by,seller_accepted_at,buyer_accepted_by,buyer_accepted_at)
  values(v_dispute.id,v_profile.id,p_resolution_type,v_qty,v_price,v_grade_id,v_amount,nullif(btrim(coalesce(p_rationale,'')),''),'pending',case when v_is_seller then v_profile.id else null end,case when v_is_seller then now() else null end,case when v_is_buyer then v_profile.id else null end,case when v_is_buyer then now() else null end)
  returning id,(seller_accepted_at is not null),(buyer_accepted_at is not null) into v_proposal_id,v_seller_accepted,v_buyer_accepted;
  update public.trade_disputes set status='proposal_pending',updated_at=now() where id=v_dispute.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'disputed',v_profile.id,jsonb_build_object('event_type','adjustment_proposed','dispute_id',v_dispute.id,'proposal_id',v_proposal_id,'resolution_type',p_resolution_type,'proposed_amount_due_bdt',v_amount));
  return query select v_proposal_id,'pending'::text,v_amount,v_seller_accepted,v_buyer_accepted;
end;$$;

create or replace function public.respond_trade_adjustment(p_proposal_id uuid,p_accept boolean,p_note text default null)
returns table(proposal_id uuid,proposal_status text,dispute_status text,trade_status text,amount_due_bdt numeric,seller_accepted boolean,buyer_accepted boolean)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;v_proposal public.trade_adjustment_proposals%rowtype;v_dispute public.trade_disputes%rowtype;v_trade public.trades%rowtype;v_is_seller boolean:=false;v_is_buyer boolean:=false;v_confirmed numeric(16,2):=0;v_initiated integer:=0;v_final_amount numeric(16,2);v_final_qty numeric(14,2);v_final_price numeric(12,2);v_final_grade uuid;v_obligation public.payment_obligations%rowtype;v_has_obligation boolean:=false;v_next_status public.trade_status;v_obligation_status text;v_seller_ok boolean;v_buyer_ok boolean;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;select * into v_profile from public.profiles where auth_user_id=auth.uid() limit 1;if not found then raise exception 'Profile not found'; end if;
  select * into v_proposal from public.trade_adjustment_proposals where id=p_proposal_id for update;if not found then raise exception 'Proposal not found'; end if;if v_proposal.status<>'pending' then raise exception 'Proposal is no longer pending'; end if;
  select * into v_dispute from public.trade_disputes where id=v_proposal.dispute_id for update;select * into v_trade from public.trades where id=v_dispute.trade_id for update;
  v_is_seller:=v_trade.seller_profile_id=v_profile.id;v_is_buyer:=exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id);
  if not (v_is_seller or v_is_buyer) then if v_profile.role='admin' then raise exception 'Commercial party acceptance is required; admin cannot substitute for seller or buyer'; end if;raise exception 'Trade participant access required';end if;
  if not coalesce(p_accept,false) then update public.trade_adjustment_proposals set status='rejected',rejected_by_profile_id=v_profile.id,rejection_note=nullif(btrim(coalesce(p_note,'')),''),updated_at=now() where id=v_proposal.id;update public.trade_disputes set status='open',updated_at=now() where id=v_dispute.id;insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'disputed',v_profile.id,jsonb_build_object('event_type','adjustment_rejected','dispute_id',v_dispute.id,'proposal_id',v_proposal.id));return query select v_proposal.id,'rejected'::text,'open'::text,'disputed'::text,v_proposal.proposed_amount_due_bdt,(v_proposal.seller_accepted_at is not null),(v_proposal.buyer_accepted_at is not null);return;end if;
  if v_is_seller and v_proposal.seller_accepted_at is null then update public.trade_adjustment_proposals set seller_accepted_by=v_profile.id,seller_accepted_at=now(),updated_at=now() where id=v_proposal.id;end if;if v_is_buyer and v_proposal.buyer_accepted_at is null then update public.trade_adjustment_proposals set buyer_accepted_by=v_profile.id,buyer_accepted_at=now(),updated_at=now() where id=v_proposal.id;end if;
  select * into v_proposal from public.trade_adjustment_proposals where id=p_proposal_id for update;v_seller_ok:=v_proposal.seller_accepted_at is not null;v_buyer_ok:=v_proposal.buyer_accepted_at is not null;if not (v_seller_ok and v_buyer_ok) then return query select v_proposal.id,'pending'::text,'proposal_pending'::text,'disputed'::text,v_proposal.proposed_amount_due_bdt,v_seller_ok,v_buyer_ok;return;end if;
  select count(*) into v_initiated from public.payments p where p.trade_id=v_trade.id and p.status='initiated';if v_initiated>0 then raise exception 'An initiated payment must be confirmed or marked failed before the adjustment can be finalized'; end if;
  select coalesce(sum(p.amount_bdt),0) into v_confirmed from public.payments p where p.trade_id=v_trade.id and p.status='confirmed';v_final_amount:=coalesce(v_proposal.proposed_amount_due_bdt,0);if v_confirmed>v_final_amount+0.01 then raise exception 'Confirmed payments exceed the proposed amount. Refund/credit handling is required before this adjustment can be finalized'; end if;
  if v_proposal.resolution_type in ('full_rejection','cancel_trade') then if v_confirmed>0.01 then raise exception 'A zero-value cancellation cannot be finalized after confirmed payment without refund handling'; end if;v_next_status:='cancelled'::public.trade_status;update public.payment_obligations set amount_due_bdt=0,status='cancelled',updated_at=now() where trade_id=v_trade.id;
  else v_final_qty:=coalesce(v_proposal.proposed_quantity_kg,v_trade.agreed_quantity_kg);v_final_price:=coalesce(v_proposal.proposed_unit_price_bdt_per_kg,v_trade.agreed_price_bdt_per_kg);v_final_grade:=coalesce(v_proposal.proposed_grade_id,v_trade.grade_id);v_final_amount:=round(v_final_qty*v_final_price,2);select * into v_obligation from public.payment_obligations where trade_id=v_trade.id for update;v_has_obligation:=found;if v_has_obligation then v_obligation_status:=case when v_final_amount<=v_confirmed+0.01 then 'paid' when v_confirmed>0 then 'partially_paid' else 'due' end;update public.payment_obligations set basis_quantity_kg=v_final_qty,unit_price_bdt_per_kg=v_final_price,amount_due_bdt=v_final_amount,status=v_obligation_status,due_at=case when v_obligation_status='paid' then due_at else coalesce(due_at,now()) end,updated_at=now() where trade_id=v_trade.id;end if;if v_has_obligation and v_final_amount<=v_confirmed+0.01 then v_next_status:='settled'::public.trade_status;else v_next_status:=v_dispute.resume_trade_status;if v_next_status='disputed' then v_next_status:='delivered'::public.trade_status;end if;end if;end if;
  update public.trade_adjustment_proposals set status='accepted',applied_at=now(),updated_at=now(),proposed_amount_due_bdt=v_final_amount where id=v_proposal.id;update public.trade_disputes set status='resolved',resolution_type=v_proposal.resolution_type,resolved_at=now(),updated_at=now() where id=v_dispute.id;update public.trades set status=v_next_status,settled_at=case when v_next_status='settled' then coalesce(settled_at,now()) else settled_at end,updated_at=now() where id=v_trade.id;
  insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,v_next_status,v_profile.id,jsonb_build_object('event_type','trade_adjustment_applied','dispute_id',v_dispute.id,'proposal_id',v_proposal.id,'resolution_type',v_proposal.resolution_type,'effective_quantity_kg',v_final_qty,'effective_unit_price_bdt_per_kg',v_final_price,'effective_grade_id',v_final_grade,'amount_due_bdt',v_final_amount,'confirmed_payments_bdt',v_confirmed));
  return query select v_proposal.id,'accepted'::text,'resolved'::text,v_next_status::text,v_final_amount,true,true;
end;$$;

create or replace function public.confirm_delivery_receipt(p_trade_id uuid,p_received_quantity_kg numeric default null,p_accepted boolean default true,p_notes text default null,p_discrepancy_reason text default null)
returns table(receipt_id uuid,receipt_status text,obligation_id uuid,amount_due_bdt numeric,trade_status text)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;v_trade public.trades%rowtype;v_shipment public.shipments%rowtype;v_receipt public.delivery_receipts%rowtype;v_obligation public.payment_obligations%rowtype;v_is_buyer boolean:=false;v_amount numeric(16,2);v_basis_qty numeric(14,2);v_basis_price numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;select * into v_profile from public.profiles where auth_user_id=auth.uid();if not found then raise exception 'Profile not found'; end if;select * into v_trade from public.trades where id=p_trade_id for update;if not found then raise exception 'Trade not found'; end if;if v_trade.status<>'delivered' then raise exception 'Trade must be delivered before buyer receipt confirmation'; end if;
  v_is_buyer:=exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id);if not (v_is_buyer or v_profile.role='admin') then raise exception 'Buyer organization or admin access required'; end if;if p_received_quantity_kg is not null and p_received_quantity_kg<=0 then raise exception 'Received quantity must be greater than zero'; end if;if not coalesce(p_accepted,true) and nullif(trim(coalesce(p_discrepancy_reason,'')),'') is null then raise exception 'Discrepancy reason is required when delivery is disputed'; end if;if exists(select 1 from public.delivery_receipts where trade_id=p_trade_id) then raise exception 'Delivery receipt has already been recorded for this trade'; end if;
  select * into v_shipment from public.shipments where trade_id=p_trade_id and status='delivered' order by delivered_at desc nulls last,created_at desc limit 1;if not found then raise exception 'Delivered shipment not found'; end if;
  v_basis_qty:=v_trade.agreed_quantity_kg;v_basis_price:=v_trade.agreed_price_bdt_per_kg;select p.proposed_quantity_kg,p.proposed_unit_price_bdt_per_kg into v_basis_qty,v_basis_price from public.trade_adjustment_proposals p join public.trade_disputes d on d.id=p.dispute_id where d.trade_id=v_trade.id and p.status='accepted' and p.applied_at is not null and p.resolution_type in ('revise_terms','partial_rejection','accept_original') order by p.applied_at desc limit 1;v_basis_qty:=coalesce(v_basis_qty,v_trade.agreed_quantity_kg);v_basis_price:=coalesce(v_basis_price,v_trade.agreed_price_bdt_per_kg);
  insert into public.delivery_receipts(trade_id,shipment_id,buyer_organization_id,confirmed_by_profile_id,received_quantity_kg,status,notes,discrepancy_reason) values(v_trade.id,v_shipment.id,v_trade.buyer_organization_id,v_profile.id,p_received_quantity_kg,case when coalesce(p_accepted,true) then 'accepted' else 'disputed' end,nullif(trim(coalesce(p_notes,'')),''),nullif(trim(coalesce(p_discrepancy_reason,'')),'')) returning * into v_receipt;
  v_amount:=round(v_basis_qty*v_basis_price,2);insert into public.payment_obligations(trade_id,buyer_organization_id,basis_quantity_kg,unit_price_bdt_per_kg,amount_due_bdt,status,due_at) values(v_trade.id,v_trade.buyer_organization_id,v_basis_qty,v_basis_price,v_amount,case when v_receipt.status='accepted' then 'due' else 'disputed' end,case when v_receipt.status='accepted' then now() else null end) returning * into v_obligation;
  if v_receipt.status='disputed' then update public.trades set status='disputed',updated_at=now() where id=v_trade.id;insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'disputed',v_profile.id,jsonb_build_object('event_type','buyer_receipt_disputed','receipt_id',v_receipt.id,'reason',v_receipt.discrepancy_reason));else insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'delivered',v_profile.id,jsonb_build_object('event_type','buyer_receipt_accepted','receipt_id',v_receipt.id,'payment_obligation_id',v_obligation.id,'amount_due_bdt',v_amount,'basis_quantity_kg',v_basis_qty,'basis_unit_price_bdt_per_kg',v_basis_price));end if;
  return query select v_receipt.id,v_receipt.status,v_obligation.id,v_obligation.amount_due_bdt,(select t.status::text from public.trades t where t.id=v_trade.id);
end;$$;

create or replace function public.confirm_trade_payment(p_payment_id uuid,p_notes text default null)
returns table(payment_id uuid,payment_status text,obligation_status text,trade_status text,total_confirmed_bdt numeric,amount_due_bdt numeric)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;v_payment public.payments%rowtype;v_trade public.trades%rowtype;v_obligation public.payment_obligations%rowtype;v_total numeric(16,2);v_obligation_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;select * into v_profile from public.profiles where auth_user_id=auth.uid();if not found then raise exception 'Profile not found'; end if;select * into v_payment from public.payments where id=p_payment_id for update;if not found then raise exception 'Payment record not found'; end if;if v_payment.status<>'initiated' then raise exception 'Only initiated payments can be confirmed'; end if;select * into v_trade from public.trades where id=v_payment.trade_id for update;if not found then raise exception 'Trade not found'; end if;
  if v_trade.status='disputed' or exists(select 1 from public.trade_disputes d where d.trade_id=v_trade.id and d.status in ('open','proposal_pending')) then raise exception 'Resolve the active dispute before confirming payment'; end if;if not (v_trade.seller_profile_id=v_profile.id or v_profile.role='admin') then raise exception 'Seller or admin confirmation required'; end if;select * into v_obligation from public.payment_obligations where id=v_payment.payment_obligation_id for update;if not found then raise exception 'Payment obligation not found'; end if;
  update public.payments set status='confirmed',confirmed_at=now(),confirmed_by_profile_id=v_profile.id,notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),updated_at=now() where id=v_payment.id;select coalesce(sum(amount_bdt),0) into v_total from public.payments where trade_id=v_trade.id and status='confirmed';
  if v_total+0.01>=v_obligation.amount_due_bdt then v_obligation_status:='paid';update public.payment_obligations set status='paid',updated_at=now() where id=v_obligation.id;update public.trades set status='settled',settled_at=now(),updated_at=now() where id=v_trade.id;insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'settled',v_profile.id,jsonb_build_object('event_type','payment_fully_confirmed','payment_id',v_payment.id,'total_confirmed_bdt',v_total,'amount_due_bdt',v_obligation.amount_due_bdt));else v_obligation_status:='partially_paid';update public.payment_obligations set status='partially_paid',updated_at=now() where id=v_obligation.id;insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,'delivered',v_profile.id,jsonb_build_object('event_type','payment_partially_confirmed','payment_id',v_payment.id,'total_confirmed_bdt',v_total,'amount_due_bdt',v_obligation.amount_due_bdt));end if;
  return query select v_payment.id,'confirmed'::text,v_obligation_status,(select t.status::text from public.trades t where t.id=v_trade.id),v_total,v_obligation.amount_due_bdt;
end;$$;

create or replace function public.mark_trade_payment_failed(p_payment_id uuid,p_reason text)
returns table(payment_id uuid,payment_status text,obligation_status text)
language plpgsql security definer set search_path=public as $$
declare v_profile public.profiles%rowtype;v_payment public.payments%rowtype;v_trade public.trades%rowtype;v_obligation public.payment_obligations%rowtype;v_confirmed numeric(16,2);v_active_dispute boolean:=false;v_obligation_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;select * into v_profile from public.profiles where auth_user_id=auth.uid();if not found then raise exception 'Profile not found'; end if;if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Failure reason is required'; end if;select * into v_payment from public.payments where id=p_payment_id for update;if not found or v_payment.status<>'initiated' then raise exception 'Initiated payment not found'; end if;select * into v_trade from public.trades where id=v_payment.trade_id;if not found then raise exception 'Trade not found'; end if;if not (v_profile.role='admin' or v_trade.seller_profile_id=v_profile.id or exists(select 1 from public.buyer_memberships bm where bm.profile_id=v_profile.id and bm.buyer_organization_id=v_trade.buyer_organization_id)) then raise exception 'Trade participant or admin access required'; end if;
  update public.payments set status='failed',notes=concat_ws(' | ',notes,'Failed: '||trim(p_reason)),updated_at=now() where id=v_payment.id;select * into v_obligation from public.payment_obligations where id=v_payment.payment_obligation_id for update;select coalesce(sum(amount_bdt),0) into v_confirmed from public.payments where trade_id=v_trade.id and status='confirmed';v_active_dispute:=exists(select 1 from public.trade_disputes d where d.trade_id=v_trade.id and d.status in ('open','proposal_pending')) or v_trade.status='disputed';v_obligation_status:=case when v_active_dispute then 'disputed' when v_confirmed>0 then 'partially_paid' else 'due' end;update public.payment_obligations set status=v_obligation_status,updated_at=now() where id=v_obligation.id;insert into public.trade_status_events(trade_id,status,changed_by_profile_id,metadata) values(v_trade.id,case when v_active_dispute then 'disputed'::public.trade_status else 'delivered'::public.trade_status end,v_profile.id,jsonb_build_object('event_type','payment_failed','payment_id',v_payment.id,'reason',trim(p_reason),'active_dispute',v_active_dispute));return query select v_payment.id,'failed'::text,v_obligation_status;
end;$$;

revoke all on function public.get_dispute_candidates() from public,anon;
revoke all on function public.get_my_disputes() from public,anon;
revoke all on function public.open_trade_dispute(uuid,text,text,text,jsonb) from public,anon;
revoke all on function public.propose_trade_adjustment(uuid,text,numeric,numeric,text,text) from public,anon;
revoke all on function public.respond_trade_adjustment(uuid,boolean,text) from public,anon;
revoke all on function public.confirm_delivery_receipt(uuid,numeric,boolean,text,text) from public,anon;
revoke all on function public.confirm_trade_payment(uuid,text) from public,anon;
revoke all on function public.mark_trade_payment_failed(uuid,text) from public,anon;
grant execute on function public.get_dispute_candidates() to authenticated;
grant execute on function public.get_my_disputes() to authenticated;
grant execute on function public.open_trade_dispute(uuid,text,text,text,jsonb) to authenticated;
grant execute on function public.propose_trade_adjustment(uuid,text,numeric,numeric,text,text) to authenticated;
grant execute on function public.respond_trade_adjustment(uuid,boolean,text) to authenticated;
grant execute on function public.confirm_delivery_receipt(uuid,numeric,boolean,text,text) to authenticated;
grant execute on function public.confirm_trade_payment(uuid,text) to authenticated;
grant execute on function public.mark_trade_payment_failed(uuid,text) to authenticated;
