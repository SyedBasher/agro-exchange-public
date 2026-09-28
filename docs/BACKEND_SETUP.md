# Backend setup sequence

The repository is now ready to move from hard-coded prototype data to persistent records.

## Recommended backend

PostgreSQL is the system of record. Supabase is a practical first hosting layer because it combines PostgreSQL, authentication, row-level security, storage and APIs without changing the underlying database model.

## Deployment sequence

1. Create/connect a Supabase project.
2. Run `database/schema.sql`.
3. Run `database/views.sql`.
4. Run `database/seed.sql` for the simulated pilot environment only.
5. Configure authentication and role mapping between auth users and `profiles.auth_user_id`.
6. Add and test row-level security before any real user data is loaded.
7. Replace hard-coded JavaScript arrays in the trading application with queries to the backend.
8. Make `Post supply` persist to `sell_offers`.
9. Make buyer-demand screens read from `open_demand_view`.
10. Make the matching screen read from deterministic matching output and store accepted matches.

## Security rules

- Browser code may use only the public/anonymous project key.
- Service-role keys must never be committed or exposed to browsers.
- Real phone numbers, NIDs, bank details and payment credentials must not be put into seed data.
- Authentication alone is not authorization. Row-level security must restrict users to the records they are entitled to change.
- Institutional analytics should be based on de-identified or aggregated data where appropriate.

## Provenance rules

The application must distinguish between:

- verified Agro-Exchange transactions,
- open seller offers,
- open buyer orders,
- official external observations,
- partner observations,
- manually verified observations,
- simulated or modelled values.

A number should not appear as a generic 'market price' unless its source class and time are known.

## First live backend milestone

The first end-to-end milestone should be deliberately narrow:

1. A test farmer signs in.
2. The farmer submits a potato offer in Bangla on a phone.
3. The record is saved to `sell_offers`.
4. A test buyer signs in and submits a compatible order.
5. The system returns the pair as a feasible match.
6. Both records remain auditable in PostgreSQL.

No payment integration is required for this milestone.
