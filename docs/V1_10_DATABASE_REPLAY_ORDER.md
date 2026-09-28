# Agro-Exchange v1.10 controlled-pilot database replay order

This file is the authoritative repository replay order for a fresh **controlled staging** database.

It does not replace live Supabase migration history. Existing staging must be changed through reviewed migrations. Do not rerun this list blindly against a populated project.

## Base schema

1. `database/schema.sql`
2. `database/views.sql`
3. `database/supabase_functions.sql`
4. `database/supabase_security.sql`
5. `database/supabase_hardening.sql`
6. `database/auth_profile_trigger.sql`

## Marketplace and trade workflow

7. `database/buyer_workflow.sql`
8. `database/buyer_verification_gate.sql`
9. `database/trade_confirmation.sql`
10. `database/qc_workflow.sql`
11. `database/qc_workflow_hardening.sql`
12. `database/logistics_workflow.sql`
13. `database/logistics_hardening.sql`
14. `database/settlement_workflow.sql`
15. `database/settlement_hardening.sql`
16. `database/dispute_workflow.sql`

## Admin, reliability and v1.8/v1.9 trust layers

17. `database/admin_operations.sql`
18. `database/admin_operations_hardening.sql`
19. `database/security_trust_hardening_v1_8.sql`
20. `database/commercial_integrity_v1_9.sql`
21. `database/transaction_liveness_v1_9.sql`
22. `database/transaction_liveness_v1_9_followup.sql`
23. `database/pilot_readiness.sql`
24. `database/pilot_readiness_hardening.sql`
25. `database/pilot_admin_bootstrap_v1_9.sql`

## v1.10 authorization and commercial-integrity overrides

These files deliberately come **after** older workflow definitions because they replace/harden selected RPCs and add final database invariants.

26. `database/lifecycle_authorization_hardening_v1_10.sql`
27. `database/dispute_party_continuity_v1_10.sql`
28. `database/cancellation_inventory_integrity_v1_10.sql`
29. `database/quantity_reconciliation_integrity_v1_10.sql`
30. `database/monetary_reconciliation_integrity_v1_10.sql`
31. `database/trade_state_machine_integrity_v1_10.sql`
32. `database/dispute_entry_continuity_v1_10.sql`

## Read-only diagnostics

Run only after schema/RPC installation:

- `database/real_jwt_account_readiness.sql`
- `database/first_admin_eligibility_preflight.sql`
- `database/buyer_promotion_readiness.sql`
- `database/operations_role_readiness.sql`
- `database/trade_state_machine_health.sql`
- `database/forensic_readonly_checks_v1_8.sql`

## Optional performance/source-data layers

Performance/index and market-source files may be applied after their corresponding base feature exists:

- `database/admin_operations_performance.sql`
- `database/dispute_performance.sql`
- `database/settlement_performance.sql`
- `database/performance_cleanup_v1_6.sql`
- `database/performance_cleanup_v1_6_followup.sql`
- `database/market_data_provenance_v1_6.sql`
- `database/market_data_hardening_v1_6.sql`
- `database/dam_source_snapshot_v1_6.sql`
- `database/matching_view_security_v1_8_1.sql`

## Synthetic seed

`database/seed.sql` is optional and **simulated-only**. Never use it to fabricate real pilot identities or substitute for Supabase Auth users.

## Release invariant

For a v1.10 pilot database, the final live definitions of the hardened functions must come from the v1.10 override layer, not an earlier file. In particular this includes:

- `initiate_trade_payment`
- `confirm_trade_payment`
- `decline_trade_confirmation`
- `propose_trade_adjustment`
- `respond_trade_adjustment`
- `open_trade_dispute`
- `restore_trade_inventory_after_cancel`

The central `trade_status_transition_guard_v1_10` trigger must also be present.
