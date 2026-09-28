-- Agro-Exchange v1.4 performance follow-up.
-- Covers foreign keys introduced by the admin/operations stage.

create index if not exists notification_outbox_trade_status_event_idx
  on public.notification_outbox(trade_status_event_id);

create index if not exists operations_sla_updated_by_idx
  on public.operations_sla_rules(updated_by_profile_id)
  where updated_by_profile_id is not null;
