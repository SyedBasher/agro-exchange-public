# Public Release Manifest

This document classifies the current Agro-Exchange repository for the clean public-source architecture.

## PUBLIC

These classes are intended for the clean public repository:

| Class | Examples | Reason |
|---|---|---|
| Application source | `index.html`, `app.js`, `app-core.js`, `styles.css`, `backend/*.js`, `backend/*.css` | Required to build/test the product |
| PWA/static assets | `assets/`, `manifest.webmanifest`, `sw.js`, `offline.html` | Required application shell |
| Public landing source | `public/` | Product-facing source |
| Database code | `database/*.sql` | Schemas, migrations, RLS and RPC logic are code, not live records |
| Synthetic fixture | `database/seed.sql` | Explicitly simulated development data only |
| Tests/CI | `scripts/`, `.github/workflows/` | Required for free public CI |
| Methodology | `docs/ARCHITECTURE.md`, `docs/BACKEND_SETUP.md` | Architecture and technical method |
| Deployment headers | `netlify.toml`, `robots.txt` | Contains no privileged secret |
| Example environment | `.env.example` | Placeholders only |

## PUBLIC, BUT SANITIZED

`backend/runtime-config.js` is generated for the public snapshot.

The generated file preserves the current build version but replaces the live Supabase project URL and publishable key with placeholders. The private repository retains the real browser runtime configuration used by staging.

`README_PUBLIC.md` becomes `README.md` in the clean public snapshot. The private README may continue to contain internal development chronology.

## PRIVATE / DO NOT EXPORT

The following current documentation is operational/internal and is excluded from the public snapshot:

- build manuals and version-finalization records;
- deployment/pilot checklists;
- Claude/Supabase forensic handoff material;
- first-admin bootstrap runbook;
- Twilio setup runbook;
- verification and remediation evidence documents.

These files do not contain credentials, but keeping them private avoids publishing operational procedures and internal audit chronology that are unnecessary for public CI.

Future files under data/raw/snapshot/export/backup/evidence/private/auth-export paths are private by default.

## REMOVE OR BLOCK IF DISCOVERED

A public release must fail if it detects:

- privileged Supabase/service-role credentials;
- database connection URLs containing passwords;
- Twilio or payment-provider secrets;
- private-key material;
- real personal email addresses or Bangladesh phone numbers in the exported source;
- database dumps, SQLite/Parquet/CSV/XLSX data exports;
- evidence files or auth/session exports.

## Current audit observations

At preparation time:

- the GitHub repository is private;
- no `.gitignore` existed, so one is being added;
- `.env.example` contains blank placeholders only;
- `database/seed.sql` is labelled simulated and uses synthetic pilot identities;
- the browser runtime contains only a Supabase publishable key/project URL, not a service-role credential;
- no public-repository history migration is planned; the public repository will begin from a clean snapshot.
