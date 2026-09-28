# Agro-Exchange

Agro-Exchange is a bilingual (Bangla/English), mobile-first B2B agricultural marketplace prototype for Bangladesh.

The platform connects farmer supply with verified buyer demand, performs deterministic eligibility/matching checks, and supports a controlled spot-trade workflow covering confirmation, selective QC, logistics, receipt, payment-status recording and disputes.

## Architecture

The browser application is a static web/PWA client. PostgreSQL/Supabase is the hosted system of record for authenticated pilot workflows.

```text
public web/PWA
      |
      v
Supabase Auth + API
      |
      +-- PostgreSQL / RLS / RPC workflows
      +-- private evidence storage
```

The repository contains source code, SQL schemas/migrations, simulated fixtures, tests and technical methodology. It does **not** contain the live pilot database, real user data, credentials or private evidence.

## Product boundary

Agro-Exchange currently records trade and payment status. It does not hold customer funds, provide escrow, guarantee settlement, or claim to operate a regulated commodity exchange.

## Matching

Matching is deterministic and fail-closed. Candidate supply/demand must satisfy commodity, grade, quantity, timing, verification and price-feasibility rules before ranking.

The current fulfilment allowance is an indicative pilot assumption, not an observed decomposition of all logistics/QC/platform costs.

## Data and privacy

Real farmer/buyer/staff data, Auth/session exports, evidence objects, raw source snapshots and operational backups remain outside this public repository.

`database/seed.sql` contains simulated development fixtures only.

## CI

GitHub Actions runs static deployment checks, JavaScript syntax checks and regression gates for the transaction/security invariants represented in the repository.

## Documentation

- `docs/ARCHITECTURE.md`
- `docs/BACKEND_SETUP.md`
- `docs/PUBLIC_REPOSITORY_POLICY.md`
- `docs/PUBLIC_RELEASE_MANIFEST.md`

## License

No open-source license is currently granted. Licensing will be considered separately.
