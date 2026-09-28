import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const required=[
  'index.html','styles.css','app.js','app-core.js','manifest.webmanifest','sw.js','offline.html','diagnostics.html','robots.txt','netlify.toml',
  'assets/agro-exchange-icon.svg','assets/agro-exchange-icon-192.png','assets/agro-exchange-icon-512.png',
  'backend/runtime-config.js','backend/auth.js','backend/pwa.js','backend/staging-guard.js','backend/market-data.js',
  'backend/v1-8-hardening.js','backend/v1-8-hardening.css','backend/v1-8-final-hardening.js','backend/v1-8-final-hardening.css','backend/v1-8-copy-integrity.js','backend/v1-9-operations.js','backend/v1-9-operations.css',
  'public/index.html','public/public.css','public/public.js'
];
const errors=[];const notes=[];
for(const rel of required){if(!fs.existsSync(path.join(root,rel)))errors.push(`Missing required file: ${rel}`);}

function read(rel){return fs.readFileSync(path.join(root,rel),'utf8');}

try{
  const manifest=JSON.parse(read('manifest.webmanifest'));
  if(manifest.display!=='standalone')errors.push('Manifest display must be standalone');
  const iconSizes=new Set((manifest.icons||[]).map(x=>String(x.sizes||'')));
  if(!iconSizes.has('192x192'))errors.push('Manifest missing 192x192 icon');
  if(!iconSizes.has('512x512'))errors.push('Manifest missing 512x512 icon');
}catch(err){errors.push(`Manifest is not valid JSON: ${err.message}`);}

const sw=read('sw.js');
for(const marker of ['.supabase.co','/rest/v1/','/auth/v1/','/storage/v1/']){
  if(!sw.includes(marker))errors.push(`Service worker backend bypass missing ${marker}`);
}
if(!sw.includes("'./public/index.html'"))errors.push('Service worker shell must include public/index.html');
if(!sw.includes("'./diagnostics.html'"))errors.push('Service worker shell must include diagnostics.html');
if(!sw.includes('backend/v1-8-final-hardening.js')||!sw.includes('backend/v1-8-final-hardening.css'))errors.push('Service worker shell must include final v1.8 hardening assets');
if(!sw.includes('backend/v1-8-copy-integrity.js'))errors.push('Service worker shell must include v1.8 economic copy-integrity guard');
if(sw.includes('demo-settlement-seed.js'))errors.push('Production service-worker shell must not cache the legacy demo settlement seed');

const runtime=read('backend/runtime-config.js');
if(/sb_secret_/i.test(runtime)||/service[_-]?role\s*[:=]\s*['\"][^'\"]+/i.test(runtime))errors.push('Runtime config appears to contain a privileged Supabase credential');
if(!/environment\s*:\s*['\"]staging['\"]/.test(runtime))errors.push('Runtime config must label this build staging');
const runtimeVersion=runtime.match(/buildVersion\s*:\s*['\"]([^'\"]+)['\"]/)?.[1];
const cacheVersion=sw.match(/CACHE_NAME=['\"]agro-exchange-shell-v([^'\"]+)['\"]/)?.[1];
if(!runtimeVersion)errors.push('Runtime config is missing buildVersion');
if(!cacheVersion)errors.push('Service worker cache name is missing a version');
if(runtimeVersion&&cacheVersion&&runtimeVersion!==cacheVersion)errors.push(`Runtime buildVersion ${runtimeVersion} does not match service-worker cache ${cacheVersion}`);

const app=read('app.js');
if(!app.includes('backend/v1-8-hardening.js'))errors.push('app.js must load the v1.8 trust guard');
if(!app.includes('backend/v1-8-final-hardening.js'))errors.push('app.js must load final v1.8 hardening');
if(!app.includes('backend/v1-8-copy-integrity.js'))errors.push('app.js must load the v1.8 economic copy-integrity guard');
if(app.includes('demo-settlement-seed.js'))errors.push('app.js must not load the legacy demo settlement seed');
if(!read('backend/auth.js').includes('sendEmailOtp'))errors.push('Auth module must include the staging email sign-in fallback');
if(!app.includes('backend/v1-9-operations.js'))errors.push('app.js must load v1.9 lifecycle operations');
if(!sw.includes('backend/v1-9-operations.js')||!sw.includes('backend/v1-9-operations.css'))errors.push('Service worker must cache v1.9 lifecycle assets');

const finalHardening=read('backend/v1-8-final-hardening.js');
if(!finalHardening.includes('ax_build_check'))errors.push('Final hardening must perform a no-cache deployed-build freshness check');
if(!finalHardening.includes('rewireDemandShortcut'))errors.push('Final hardening must replace the obsolete Post demand prototype shortcut');
if(!finalHardening.includes('installOperationalActionGuard'))errors.push('Final hardening must guard rapid operational transaction actions');
if(!finalHardening.includes('markSimulatedWidgets'))errors.push('Final hardening must per-widget label simulated dashboard content');

const copyIntegrity=read('backend/v1-8-copy-integrity.js');
if(!copyIntegrity.includes('net economic room')||!copyIntegrity.includes('quantity coverage'))errors.push('Match copy must describe the implemented ranking inputs');
if(!copyIntegrity.includes('one indicative route allowance')||!copyIntegrity.includes('not observed component costs'))errors.push('Fulfilment copy must not claim an unimplemented observed cost decomposition');

const finalCss=read('backend/v1-8-final-hardening.css');
if(!finalCss.includes('min-width:44px')||!finalCss.includes('100dvh'))errors.push('Final hardening CSS must retain touch-target and dynamic-viewport safeguards');

const netlify=read('netlify.toml');
for(const marker of ['X-Robots-Tag','noindex','Service-Worker-Allowed','Permissions-Policy']){
  if(!netlify.includes(marker))errors.push(`Netlify staging header missing ${marker}`);
}

const robots=read('robots.txt');
if(!/Disallow:\s*\//.test(robots))errors.push('Staging robots.txt must disallow crawling');

const index=read('index.html');
if(!index.includes('app.js'))errors.push('index.html does not load app.js');

const publicIndex=read('public/index.html');
for(const ref of ['public.css','public.js'])if(!publicIndex.includes(ref))errors.push(`public/index.html missing ${ref}`);

const diagnostics=read('diagnostics.html');
if(!diagnostics.includes('Supabase public reachability'))errors.push('Device diagnostics lacks backend reachability check');
if(/agroExchangeAccessToken[^\n]{0,80}(textContent|innerHTML|console)/i.test(diagnostics))errors.push('Diagnostics may expose an auth token');

if(errors.length){
  console.error('\nAgro-Exchange static smoke check FAILED\n');
  for(const e of errors)console.error(' - '+e);
  process.exit(1);
}
notes.push(`Checked ${required.length} required deployment files`);
notes.push(`Runtime/cache build identity aligned at ${runtimeVersion}`);
notes.push('Manifest, service-worker backend bypass, staging headers, trust/copy guards, runtime config and diagnostics checks passed');
console.log('Agro-Exchange static smoke check PASSED');
for(const n of notes)console.log(' - '+n);
