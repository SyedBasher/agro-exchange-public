# Public-source deployment

The public repository contains only a placeholder `backend/runtime-config.js`.

A real deployment must generate the browser-safe runtime configuration at build time from hosting environment variables. Netlify runs:

```
node scripts/generate-runtime-config.mjs
```

Required variables:

- `AGRO_SUPABASE_URL`
- `AGRO_SUPABASE_PUBLISHABLE_KEY`

Optional variables:

- `AGRO_APP_ENVIRONMENT` — defaults to `staging`
- `AGRO_BUILD_VERSION` — otherwise read from the committed placeholder runtime config

Only a browser publishable/anon Supabase key belongs here. Never use a service-role key, database password, SMS-provider secret, payment-provider secret, refresh token or other privileged credential.

The generator fails the build if the required values are absent or if the key appears privileged. This is deliberate: a hosted deployment must not silently ship the placeholder project.

Real user data, evidence and operational records remain in the private hosted database/storage and are never generated into the public source repository.
