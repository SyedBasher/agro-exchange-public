// Public-source runtime configuration.
// Use deployment-time values for any real environment. Never place privileged credentials in browser code.
window.AGRO_EXCHANGE_CONFIG = window.AGRO_EXCHANGE_CONFIG || {
  mode: 'supabase',
  environment: 'staging',
  buildVersion: '1.10',
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  anonKey: 'YOUR_SUPABASE_PUBLISHABLE_KEY',
  accessToken: ''
};
