# Agro-Exchange real-JWT pilot role test matrix

This document defines the minimum staging authorization harness for v1.10. It contains no private identities, credentials, tokens, or operational evidence.

## Test-account principle

Use the smallest practical set of controlled staging accounts owned by authorized pilot participants. Do not reuse the only farmer account as an admin account. Promotion to admin must remain a separate, explicit step after the target Auth/profile account is identified and confirmed.

Minimum independent role accounts for full authorization testing:

- Farmer
- Buyer
- QC operator
- Field agent
- Transporter
- Admin

If operational roles cannot all be provisioned immediately, farmer and buyer tests can proceed first. Missing roles are recorded as **not executed**, never as passed.

## Session-routing tests

| Case | Expected result |
| --- | --- |
| Fresh farmer login | Seller workspace opens once |
| Farmer navigates away | User-selected view remains |
| Reload in same authenticated session | No forced return to seller workspace |
| Silent access-token refresh | No forced return to seller workspace |
| Sign out, then later fresh farmer login | Seller workspace opens once again |
| Fresh buyer login | Demand/procurement workspace opens once |
| Unverified farmer | Can inspect seller flow; publishing remains disabled and clearly explained |
| Verified farmer | Publishing control is enabled, subject to live backend readiness |
| Unknown/future operational role | No guessed role-home redirect |

## Authorization matrix

Each row requires both the browser/JWT path and the database/RPC authorization boundary to agree.

| Role | Positive test | Negative test |
| --- | --- | --- |
| Farmer | Verified farmer can post supply | Farmer cannot post buyer demand |
| Buyer | Verified approved buyer can post demand | Buyer cannot post farmer supply |
| QC operator | Assigned QC operator can act on assigned trade | QC operator cannot inspect or mutate an unassigned trade |
| Field agent | Assigned field agent can perform explicitly delegated field workflow | Field agent cannot accept commercial adjustments for buyer or seller |
| Transporter | Assigned transporter can update permitted logistics state | Transporter cannot alter quantity, price, payment basis, or other commercial terms |
| Admin | Admin can perform documented administrative actions | Admin cannot substitute for buyer/seller commercial consent |
| Any signed-out user | Can view permitted public/simulated information | Cannot perform authenticated transaction actions |

## Fail-closed expectations

- Missing/expired JWT: transaction action fails.
- Missing Agro-Exchange profile: transaction action fails.
- Role mismatch: action fails.
- Verification/organization approval missing where required: action fails.
- Assigned-operator scope missing: QC/logistics action fails.
- RPC or database error: UI must not display a fake success.
- Simulated market/intelligence data must remain visually distinguishable from live transaction state.

## Evidence to capture during execution

For each executed case, record only non-secret evidence:

1. test date and build/commit SHA;
2. role under test;
3. action attempted;
4. expected result;
5. observed result;
6. PASS/FAIL;
7. sanitized error category if failed.

Never store access tokens, refresh tokens, magic-link URLs, private email addresses, phone numbers, or service-role credentials in this public repository.

## First-admin gate

Do not execute `bootstrap_first_admin(uuid)` until:

1. the live Auth/profile state has been inspected;
2. the exact account to be promoted has been identified;
3. an independent farmer test account will remain available;
4. the account owner has explicitly confirmed the promotion.

The first-admin operation is not part of automated public CI.
