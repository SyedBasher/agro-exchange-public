# Agro-Exchange architecture v1.8.1

## 1. Product boundary

Agro-Exchange is a bilingual Bangla/English, mobile-first B2B agricultural marketplace for Bangladesh. It combines market information, farmer supply, buyer procurement demand, deterministic matching and a controlled spot-trade fulfilment workflow.

The current product is **not** a regulated commodity exchange, escrow provider, lender, insurer or payment processor. It records payment status and references but does not hold or move customer funds. Digital Trade Confirmation is a platform transaction record, not a claim of legally binding exchange-contract status without separate legal review.

## 2. Product surfaces

### Public site

`public/index.html`

Purpose:
- explain the controlled pilot;
- present selected market/source information with clear provenance;
- direct farmers, buyers and institutions into the trading application.

### Trading web/PWA

Root `index.html`

Purpose:
- farmer supply and buyer demand;
- transparent matching;
- two-party trade confirmation;
- selective QC and weighing;
- logistics and delivery;
- receipt and payment-status recording;
- disputes and mutually accepted adjustments;
- admin operations, notifications and pilot telemetry.

Farmer-facing flows are phone-first and Bangla-capable. Buyer/admin screens may use denser layouts on larger devices.

## 3. High-level architecture

```text
Public site                         Trading web/PWA
    |                                     |
    +------------------+------------------+
                       |
                       v
                 Browser application
        Bangla/English + mobile trust guards
                       |
        +--------------+----------------+
        |                               |
        v                               v
 Static shell/PWA                 Supabase API
 manifest/SW/offline        publishable key + user JWT
        |                               |
        |                     +---------+---------+
        |                     |                   |
        |                     v                   v
        |              PostgreSQL + RLS     Private Storage
        |                     |              QC/delivery/dispute
        |                     |
        |                     +-- identity/roles
        |                     +-- supply/demand/matching
        |                     +-- confirmations/trades
        |                     +-- QC/logistics
        |                     +-- receipt/payment status
        |                     +-- disputes/adjustments
        |                     +-- admin/alerts/escalation
        |                     +-- reliability/QC telemetry
        |                     +-- market-source provenance
        +-----------------------------------------------+
```

The browser contains only the Supabase project URL and publishable key. Service-role credentials, database passwords, SMS-provider secrets, payment-provider secrets and user tokens must never be committed to GitHub.

## 4. Identity, authorization and verification

`profiles` maps Supabase Auth users to one role:

- `farmer`
- `buyer`
- `field_agent`
- `qc_operator`
- `transporter`
- `admin`

New self-service Auth users are provisioned as **unverified farmers**. Buyer and operational roles are approval-based. Buyers also need membership in a verified buyer organization.

### v1.8 security boundary

The browser no longer has direct authenticated `INSERT/UPDATE/DELETE` privileges on:

- `profiles`;
- `farms`;
- `sell_offers`;
- `buy_orders`.

This closes the two most serious Round-1 audit paths: self-changing `role/verified`, and directly rewriting commercial inventory/status around the RPC layer.

Safe self-service profile changes are exposed only through `update_my_profile_preferences()`, which can change display name/language but has no role or verification parameter.

`current_profile_id()` and `current_user_role()` remain side-effect-free caller-context helpers and are explicitly executable by `authenticated` because RLS policies depend on them.

Farmer and buyer verification are now symmetric at new-trade entry: new farmer supply requires a verified farmer; buyer demand requires a verified buyer in a verified buyer organization; verification is rechecked when a trade confirmation is formed/accepted.

## 5. Supply, demand and matching

Core entities:

```text
profiles -> farms
buyer_organizations -> buyer_memberships
commodities -> commodity_grades
locations
sell_offers
buy_orders
matches
```

### Authoritative transaction path

In Supabase staging/production mode, supply and demand mutations are RPC-owned. Client-local models are not authoritative transaction engines and may not be presented as live matches.

### Hard feasibility

A candidate must satisfy:

1. same commodity;
2. buyer grade requirement, if specified, must be explicitly satisfied by seller grade;
3. positive remaining quantities;
4. overlapping seller/buyer date windows;
5. positive, non-null seller floor and buyer target prices;
6. verified counterparties;
7. buyer target minus seller floor must cover the current **indicative fulfilment allowance**.

The current allowance is a pilot routing assumption exposed by one database function. It is deliberately **not** represented as observed collection + QC + transport + platform-cost decomposition.

### Ranking

After hard feasibility:

Seller-side ordering:

```text
net economic room DESC
seller quantity coverage DESC
earliest feasible date ASC
buy_order_id ASC
```

Buyer-side ordering:

```text
net economic room DESC
buyer quantity coverage DESC
earliest feasible date ASC
sell_offer_id ASC
```

The final UUID ordering is a deterministic tie-breaker.

For API compatibility, `match_score` remains and currently combines 60% normalized net economic room and 40% relevant quantity coverage. User-facing copy should explain the actual factors rather than imply an opaque reliability/timing-weighted formula. Timing is currently an ordering tie-breaker; verification is a hard gate, not a score bonus.

## 6. Trade confirmation and state machine

A candidate match does not create a trade automatically.

`trade_confirmations` snapshots the offer/order, parties, commodity/grade, route, quantity, unit price, delivery terms, payment terms and QC requirement. Price and quantity must be positive. Only after seller and buyer independently accept the same confirmation is a trade created and remaining supply/demand reduced atomically.

```text
Supply + Demand
    -> feasible match
    -> Digital Trade Confirmation
    -> both parties accept
    -> confirmed
         +-- QC required -> awaiting_qc -> ready_for_dispatch
         |                    \-> disputed if rejected
         +-- QC waived ----------------> ready_for_dispatch
                                          -> shipment assigned
                                          -> transporter accepts
                                          -> in_transit
                                          -> delivered
                                              +-> buyer receipt accepted
                                              |     -> payment due
                                              |     -> buyer records initiated
                                              |     -> seller confirms received
                                              |     -> settled
                                              \-> dispute -> proposal -> two-party resolution
```

State-changing RPCs use row locking/status checks and database constraints where appropriate. Original agreed trade terms are retained for audit.

## 7. QC architecture

QC is selective, not mandatory third-party inspection for every trade.

QC records can contain measured weight, accepted grade, decision, weighing method, scale certification metadata, evidence, inspection level, reason and direct QC cost.

Measured weight does **not** silently rewrite agreed commercial quantity or the payment obligation. A commercial change belongs in the dispute/adjustment process.

A QC operator can update telemetry only for their own inspection record; admin retains oversight authority.

Pilot comparisons of QC-required and QC-bypassed trades remain descriptive, not automatically causal.

## 8. Logistics, receipt and settlement

A partial unique index enforces one active shipment per trade for `assigned/accepted/in_transit` states.

Delivery proof is private and participant/role scoped.

After delivery, the buyer confirms receipt. Default payment obligation is based on the agreed commercial quantity × agreed unit price unless both parties later accept a separate adjustment.

Normal payment authority is intentionally split:

```text
buyer organization -> records payment initiated/reference
seller             -> confirms funds actually received
system             -> settles only when confirmed amount covers obligation
```

An admin does not silently perform both commercial sides of the ordinary settlement flow.

## 9. Dispute and commercial adjustment

Evidence never automatically edits the original agreement.

```text
issue
 -> dispute
 -> resolution proposal
 -> proposer acceptance
 -> counterparty acceptance/rejection
 -> accepted proposal changes effective settlement basis
```

The original `trades.agreed_*` values remain historically recoverable. Operational escalation cannot substitute for commercial consent.

## 10. Admin, performance and privacy boundary

Admin capabilities include profile/role approval, buyer-organization verification, SLA thresholds, exception escalation, audit history and source-data promotion.

Performance history exposes observable components and sample depth rather than a star/black-box rating. Current verified-account performance RPCs permit counterparty history visibility; this is an intentional marketplace-transparency choice for the controlled pilot and must be revisited if pilot privacy expectations require narrower participant-only visibility.

Admin→admin second approval remains a later scaling question, not a current pilot feature.

## 11. External market-data provenance

External market information follows:

```text
source registration
 -> retrieval run
 -> raw source record
 -> mapping/validation
 -> reuse status cleared
 -> admin promotion
 -> verified market observation
```

Raw source capture is not automatically a verified observation. Publisher, URL, retrieval time, published ranges and provenance are retained. Promotion requires explicit commodity, geography, timestamp and supported unit context.

The initial Bangladesh Department of Agricultural Marketing capture remains intentionally unpromoted where source context is insufficient.

## 12. Simulated vs live data

The platform distinguishes:

- simulated development/dashboard values;
- source-backed external observations;
- platform open offers/orders;
- verified platform transactions;
- modelled/indicative assumptions.

v1.8 adds per-widget SIMULATED labels to the static overview KPIs/opportunity and corrects matching/fulfilment copy so illustrative component examples are not confused with the live matching cost model.

Legacy demo transaction seeding is removed from the production bootstrap. Operational transaction actions require authentication/profile context in Supabase mode; device-local demonstration data are not actionable as real transactions.

## 13. Bangla/English and farmer-first UX

The main app now persists language choice and can synchronize the signed-in profile preference through the safe preference RPC.

The farmer home route is Sell Produce rather than an analytics-heavy overview. Buyer accounts route toward procurement demand.

Farmer commodity/grade/location values, key accessibility labels and recognized server errors are localized. Unknown server errors in Bangla mode fall back to a safe Bangla message instead of exposing raw PostgreSQL text.

The obsolete Post Demand prototype shortcut is rewired to the real buyer workflow.

## 14. Mobile/PWA trust boundary

The static shell can reopen after a successful online visit. Live account/transaction data still require connectivity; there is no offline transaction synchronization.

Supabase Auth, REST and Storage requests are excluded from service-worker caching.

v1.8.1 adds:

- a cache namespace tied to build `1.8.1`;
- a no-cache runtime build check that warns an installed stale client to reload;
- shared real backend reachability state between health/PWA UI;
- 44px minimum target safeguards for key controls;
- `dvh` safeguards for transactional sheets;
- visible failure behavior when a required trust module cannot load.

## 15. Automated and live verification boundary

CI now checks static deployment integrity, JavaScript syntax and v1.8 forensic regression invariants covering the known Round-1 security/trust defects.

Live Supabase checks have additionally confirmed the new direct-write privilege posture, caller-helper EXECUTE privileges, matching candidates and active-shipment unique index.

This is **not** equivalent to a real authenticated end-to-end test. The system still needs genuine separate farmer/buyer/operational accounts on physical devices before pilot-readiness can be called verified.

## 16. Supabase advisory posture

Supabase may warn that signed-in users can execute browser-facing `SECURITY DEFINER` RPCs. That warning is expected only where such exposure is intentional; each RPC must continue to perform explicit auth/role/ownership checks and remain narrow.

Performance `unused_index` notices are informational in the current low-workload database and are not grounds for deleting indexes before representative pilot traffic exists.

## 17. Claude Round 2 audit model

Round 1 was static-file-only. Round 2 should receive **authorized read-only Supabase access** so the auditor can compare:

```text
GitHub code/migrations
        vs
live migration history
        vs
live grants/RLS/functions/indexes/advisors
```

Use `docs/CLAUDE_ROUND2_SUPABASE.md` and `database/forensic_readonly_checks_v1_8.sql`. Do not paste service-role keys, database passwords or private provider secrets into prompts or repository files.

## 18. Remaining launch gate

Before a real-user pilot:

1. finish PR/CI review and merge v1.8.1 only if clean;
2. deploy the exact merged build to controlled HTTPS staging;
3. enable a legitimate authentication route and provision separate test roles;
4. run adversarial authorization checks with real JWTs;
5. run the full multi-account/multi-device transaction chain;
6. repeat the forensic review with live Supabase access;
7. resolve any new material findings before the very small controlled pilot.
