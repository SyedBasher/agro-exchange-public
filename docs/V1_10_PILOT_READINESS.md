# Agro-Exchange v1.10 controlled-pilot release readiness

This document records repository and live-staging release gates for PR #3.

## Repository release-candidate gates

Current source must satisfy all of the following:

- public-release safety audit passes;
- static deployment smoke check passes;
- v1.8 and v1.9 regressions pass;
- v1.10 Auth regression passes;
- v1.10 authorization/commercial-integrity contract passes;
- v1.10 release-candidate repository gate passes;
- `docs/V1_10_DATABASE_REPLAY_ORDER.md` remains the authoritative fresh-database order;
- production bootstrap excludes legacy demo settlement seeding.

## Live Supabase gates already verified

- live project is healthy;
- browser-facing lifecycle RPCs exist with one unambiguous signature each;
- v1.10 lifecycle/dispute/inventory/quantity/monetary/state-machine hardening is installed;
- central trade-state transition guard is live and internal-only;
- state-machine health audit currently reports zero anomalies;
- no live trade/payment/shipment data existed when the v1.10 integrity triggers were installed.

## Real-identity gate — NOT YET COMPLETE

Current staging identity state at the latest review:

- Auth users: 1
- Auth-linked profiles: 1
- linked farmers: 1
- linked buyers: 0
- linked admins: 0
- linked QC operators: 0
- linked field agents: 0
- linked transporters: 0
- eligible non-original unverified farmer candidates: 0

The existing Auth-linked farmer must remain a farmer.

## Required next real-user sequence

1. A second authorized participant signs in through normal staging Auth.
2. Re-run first-admin eligibility preflight.
3. With explicit operator confirmation, bootstrap the **second account only** as first admin.
4. A third authorized participant signs in normally.
5. Admin promotes the third linked profile to verified buyer and links it to a verified buyer organization.
6. Run farmer/buyer positive and negative real-JWT tests.
7. Add separate controlled Auth users for QC operator, field agent and transporter.
8. Run role-specific JWT tests.
9. Run one complete multi-account trade:
   - farmer posts supply;
   - buyer posts demand;
   - feasible match;
   - bilateral confirmation;
   - selective QC or explicit QC waiver;
   - shipment assignment/acceptance/dispatch/delivery;
   - buyer receipt;
   - payment-status/reference initiation;
   - seller receipt confirmation;
   - settlement.
10. Run at least one dispute path with bilateral adjustment/rejection.
11. Run `database/trade_state_machine_health.sql`; every anomaly count must be zero.
12. Repeat live Supabase security/forensic review.

## Pilot stop conditions

Do not proceed with the controlled pilot if any of the following is true:

- CI is not clean on the exact release head;
- database replay order or live RPC definitions are ambiguous;
- any real-JWT role boundary fails;
- state-machine health reports a non-zero anomaly;
- a commercial action can succeed after its required authorization/evidence gate fails;
- participant secrets or real operational data appear in the public repository.

Repository-clean does **not** mean real-user-pilot verified. The real-identity and multi-account transaction gates remain mandatory.
