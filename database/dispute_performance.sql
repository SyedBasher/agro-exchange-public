-- Agro-Exchange v1.3: indexes for foreign keys introduced by dispute/adjustment workflow

create index if not exists adjustment_proposals_buyer_accepted_by_idx
  on public.trade_adjustment_proposals(buyer_accepted_by)
  where buyer_accepted_by is not null;

create index if not exists adjustment_proposals_seller_accepted_by_idx
  on public.trade_adjustment_proposals(seller_accepted_by)
  where seller_accepted_by is not null;

create index if not exists adjustment_proposals_rejected_by_idx
  on public.trade_adjustment_proposals(rejected_by_profile_id)
  where rejected_by_profile_id is not null;

create index if not exists adjustment_proposals_grade_idx
  on public.trade_adjustment_proposals(proposed_grade_id)
  where proposed_grade_id is not null;
