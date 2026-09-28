# v1.10 controlled-pilot identity onboarding

The currently published Netlify staging site is still the older v1.9 frontend build. It may be used **only to establish genuine Supabase Auth identities** because it points to the same live Supabase project and uses the normal OTP/Magic-Link Auth path.

Do not use the v1.9 deployed frontend for v1.10 transaction validation.

## Second participant

1. Open the controlled staging site.
2. Use a separate test email account controlled by the participant/operator.
3. Complete the normal staging sign-in flow.
4. Do not copy or share the password, Magic-Link URL, access token, refresh token or OTP with another person or into GitHub.
5. The live Auth trigger creates an unverified farmer profile automatically.
6. Run `database/pilot_identity_stage.sql`.
7. Continue only when the result is `FIRST_ADMIN_CANDIDATE_READY`.

The original linked farmer must remain unchanged.

## First admin

The first-admin bootstrap is an exceptional one-time operation. Before it runs:

- there must be at least two genuine Auth users;
- there must be at least two Auth-linked profiles;
- the target must be the non-original unverified farmer candidate;
- no admin may already exist;
- the operator must explicitly confirm the promotion target.

After bootstrap, re-run `database/pilot_identity_stage.sql`.

## Buyer participant

A third independent participant then signs in through normal Auth and is initially created as an unverified farmer. The real admin promotes that profile to verified buyer and attaches it to a verified buyer organization through the normal admin workflow.

The target stage is then `CORE_TRADING_READY_OPERATIONS_PENDING`.

## Operational roles

Additional independent controlled Auth identities are provisioned for:

- QC operator
- field agent
- transporter

After all are verified and linked, the diagnostic should report `FULL_ROLE_MATRIX_READY`.

## Deployment boundary

Identity creation may use the currently published v1.9 staging frontend because Auth points to the same Supabase project.

All real-JWT transaction tests, commercial workflow tests and the first end-to-end trade must wait until the **v1.10 release-candidate frontend** is deployed. Repository correctness and live database hardening do not make the old v1.9 browser build a valid v1.10 transaction client.
