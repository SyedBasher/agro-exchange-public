# Backend setup sequence — v1.10 controlled pilot

PostgreSQL/Supabase is the Agro-Exchange system of record. The browser uses only the Supabase project URL, publishable key and the signed-in user's JWT. Privileged credentials never belong in browser code or GitHub.

## Authoritative database replay

For a fresh controlled staging database, follow **`docs/V1_10_DATABASE_REPLAY_ORDER.md`**.

Do not reconstruct the database by running only `schema.sql`, `views.sql` and `seed.sql`. Later files intentionally replace and harden earlier RPC definitions. The v1.10 override layer must be applied after the older workflow definitions.

For an existing Supabase project, use reviewed migrations and verify the live definitions after each security-sensitive change. Do not blindly replay the fresh-database sequence against populated staging.

## Authentication and roles

Supabase Auth creates genuine identities. The profile trigger provisions a new Auth user as an **unverified farmer**.

Pilot roles are:

- farmer
- buyer
- qc_operator
- field_agent
- transporter
- admin

Buyer and operational roles are approval-based. Buyers additionally require membership in a verified buyer organization.

Never fabricate pilot identities by inserting directly into `auth.users`. Never commit access/refresh tokens, magic links, passwords or participant contact details.

## Authoritative transaction path

New supply, demand and lifecycle mutations are RPC-owned. Browser code must not directly mutate protected lifecycle tables.

The controlled trade chain is:

```text
verified supply + verified demand
 -> feasible match
 -> two-party trade confirmation
 -> confirmed
 -> selective QC / QC waiver
 -> ready_for_dispatch
 -> shipment assignment + transporter acceptance
 -> in_transit
 -> delivered
 -> buyer receipt
 -> payment-status/reference recording
 -> seller payment confirmation
 -> settled
```

Disputes suspend the normal path and require bilateral commercial resolution. Admin may coordinate but cannot substitute for buyer/seller commercial consent.

## v1.10 integrity layer

The v1.10 database adds defense-in-depth for:

- first-admin bootstrap eligibility;
- buyer and operational-role JWT readiness;
- buyer-side lifecycle authorization;
- historical dispute-party continuity;
- cancellation/inventory restoration;
- quantity reconciliation;
- monetary reconciliation;
- a central trade-state transition guard.

Run `database/trade_state_machine_health.sql` during pilot diagnostics. Any non-zero anomaly count requires investigation before continuing transactions.

## Synthetic data

`database/seed.sql` is simulated development data only. It is not an Auth-user provisioning mechanism and must never be used to claim a real multi-user test passed.

## Pilot release gate

Repository/CI correctness is necessary but not sufficient. Before a real-user pilot:

1. exact branch/build must pass public-release and static smoke CI;
2. live Supabase must match the v1.10 hardened function/trigger definitions;
3. independent real Auth identities must exist for farmer, admin and buyer, followed by QC/field-agent/transporter roles;
4. real-JWT positive and negative role tests must pass;
5. a full multi-account transaction must complete from supply/demand through settlement/dispute paths;
6. state-machine health audit must remain zero-anomaly;
7. no pilot user secrets or operational data may be committed to the public repository.
