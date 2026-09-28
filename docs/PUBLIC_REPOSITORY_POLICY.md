# Public Repository Policy

## Purpose

The public Agro-Exchange repository is a **source-code, schema, methodology and CI repository**. It is not the system of record for pilot users, transactions or evidence.

The public repository exists so the application code and automated checks can be inspected and run without placing real operational data in GitHub.

## Public

The clean public snapshot may contain:

- application JavaScript/CSS/HTML;
- PWA assets;
- CI workflows and regression tests;
- database schemas and migrations;
- simulated seed fixtures that are explicitly labelled simulated;
- architecture and backend methodology;
- deployment configuration that contains no secret;
- browser-safe example configuration.

Database functions and RLS logic are treated as code. Security must not depend on keeping their source hidden.

## Private

The following must remain outside the public repository:

- real farmer, buyer, staff or transporter records;
- real email addresses, phone numbers, NIDs or other identity data;
- Auth exports, access tokens, refresh tokens or session data;
- service-role keys, database passwords, SMS-provider secrets and payment-provider secrets;
- QC, delivery and dispute evidence objects;
- live transaction exports;
- raw source snapshots and private datasets;
- SQLite/Parquet/database dumps and backups;
- internal forensic handoffs, operational runbooks and pilot evidence;
- local tool state and logs.

The live hosted database remains private in Supabase/PostgreSQL. Private evidence remains in restricted Storage buckets.

## Repository history rule

Do **not** change the existing private repository to public.

A new public repository must be created from a sanitized snapshot so the old private Git history, branches, PR discussions and previously deleted material are never exposed merely by changing repository visibility.

## Configuration rule

A Supabase publishable browser key is not a privileged secret, but the public snapshot still uses a sanitized runtime configuration so the public CI repository is not coupled to the live pilot project.

Privileged credentials must never be added to client-side code, GitHub Actions variables, fixtures or documentation committed to the public repository.

## Data rule

No real operational data belongs in Git.

Simulated fixtures may be public only when they are clearly synthetic and contain no real person's information. Any future CSV/Parquet/SQLite/raw-source dataset is private by default unless deliberately reviewed and approved for publication.

## Release process

1. Develop in the private working repository.
2. Run the public-release audit.
3. Generate a clean public snapshot from the whitelist.
4. Inspect the generated diff.
5. Push only the clean snapshot to the separate public repository.
6. Let public GitHub Actions run on the public code.
7. Keep live data, credentials and operational evidence in private systems.

## Licensing

No open-source license is introduced by this policy. Public visibility alone is not a decision to grant a general reuse license. Licensing can be decided separately before wider release.
