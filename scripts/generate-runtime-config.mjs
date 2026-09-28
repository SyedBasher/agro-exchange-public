import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const target=path.join(root,'backend','runtime-config.js');

function need(name){
  const value=String(process.env[name]||'').trim();
  if(!value)throw new Error(`Missing required deployment variable: ${name}`);
  return value;
}

const supabaseUrl=need('AGRO_SUPABASE_URL').replace(/\/$/,'');
const publishableKey=need('AGRO_SUPABASE_PUBLISHABLE_KEY');
const environment=String(process.env.AGRO_APP_ENVIRONMENT||'staging').trim()||'staging';

if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(supabaseUrl)){
  throw new Error('AGRO_SUPABASE_URL must be an https://<project>.supabase.co URL');
}
if(/sb_secret_/i.test(publishableKey)||/service[_-]?role/i.test(publishableKey)){
  throw new Error('Privileged Supabase credentials must never be written to browser runtime config');
}
if(!/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey) && !/^eyJ[A-Za-z0-9._-]+$/.test(publishableKey)){
  throw new Error('AGRO_SUPABASE_PUBLISHABLE_KEY does not look like a browser publishable/anon key');
}
if(!['staging','production','development'].includes(environment)){
  throw new Error('AGRO_APP_ENVIRONMENT must be staging, production or development');
}

let buildVersion=String(process.env.AGRO_BUILD_VERSION||'').trim();
if(!buildVersion){
  const existing=fs.readFileSync(target,'utf8');
  buildVersion=existing.match(/buildVersion\s*:\s*['"]([^'"]+)['"]/)?.[1]||'';
}
if(!/^\d+\.\d+(?:\.\d+)?$/.test(buildVersion)){
  throw new Error('Unable to determine a valid AGRO_BUILD_VERSION');
}

const content=`// Generated at deploy time. Do not commit live environment values.
window.AGRO_EXCHANGE_CONFIG = window.AGRO_EXCHANGE_CONFIG || {
  mode: 'supabase',
  environment: ${JSON.stringify(environment)},
  buildVersion: ${JSON.stringify(buildVersion)},
  supabaseUrl: ${JSON.stringify(supabaseUrl)},
  anonKey: ${JSON.stringify(publishableKey)},
  accessToken: ''
};
`;

fs.writeFileSync(target,content,'utf8');
console.log(`Generated browser runtime config for ${environment} build ${buildVersion}`);
