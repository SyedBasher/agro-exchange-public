import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const read=rel=>fs.readFileSync(path.join(root,rel),'utf8');
const errors=[];
const pass=[];
function must(condition,message){if(condition)pass.push(message);else errors.push(message);}
function versionAtLeast(actual,minimum){
  const a=String(actual||'').split('.').map(Number),m=String(minimum||'').split('.').map(Number);
  for(let i=0;i<Math.max(a.length,m.length);i++){const av=a[i]||0,mv=m[i]||0;if(av>mv)return true;if(av<mv)return false;}
  return true;
}

const migration=read('database/security_trust_hardening_v1_8.sql');
const viewSecurity=read('database/matching_view_security_v1_8_1.sql');
const app=read('app.js');
const hardening=read('backend/v1-8-hardening.js');
const finalHardening=read('backend/v1-8-final-hardening.js');
const copyIntegrity=read('backend/v1-8-copy-integrity.js');
const finalCss=read('backend/v1-8-final-hardening.css');
const runtime=read('backend/runtime-config.js');
const sw=read('sw.js');
const health=read('backend/health.js');
const pwa=read('backend/pwa.js');

// F-01: no unrestricted authenticated profile mutation.
must(/revoke\s+insert,\s*update,\s*delete\s+on\s+table\s+public\.profiles\s+from\s+authenticated/i.test(migration),'F-01 profile direct writes revoked');
must(/update_my_profile_preferences/i.test(migration),'Safe profile preference RPC exists');
must(!/grant\s+update\s+on\s+(table\s+)?public\.profiles\s+to\s+authenticated/i.test(migration),'No table-wide profile UPDATE re-grant');

// F-02: supply/demand inventory is RPC-only.
must(/revoke\s+insert,\s*update,\s*delete\s+on\s+table\s+public\.sell_offers\s+from\s+authenticated/i.test(migration),'F-02 sell offer direct writes revoked');
must(/revoke\s+insert,\s*update,\s*delete\s+on\s+table\s+public\.buy_orders\s+from\s+authenticated/i.test(migration),'F-02 buy order direct writes revoked');

// F-23: RLS helper functions are callable by authenticated users.
must(/grant\s+execute\s+on\s+function\s+public\.current_profile_id\(\)\s+to\s+authenticated/i.test(migration),'F-23 current_profile_id EXECUTE restored');
must(/grant\s+execute\s+on\s+function\s+public\.current_user_role\(\)\s+to\s+authenticated/i.test(migration),'F-23 current_user_role EXECUTE restored');

// Matching safety and explainability.
must(/net_price_room_bdt_per_kg/i.test(migration),'Matching computes net price room after indicative fulfilment allowance');
must(/and\s+d\.target_price_bdt_per_kg-s\.minimum_price_bdt_per_kg\s*>=/i.test(migration),'F-04 matching has a hard economic feasibility gate');
must(/minimum price must be greater than zero/i.test(migration),'F-06 seller price validation is server-side');
must(/target price must be greater than zero/i.test(migration),'F-06 buyer price validation is server-side');
must(/price must be greater than zero/i.test(migration),'Trade confirmation price validation is server-side');
must(/d\.grade_code is null\s+or \(s\.grade_code is not null and s\.grade_code=d\.grade_code\)/i.test(migration),'F-28 buyer grade requirement cannot wildcard through missing seller grade');
must(/seller_quantity_coverage/i.test(migration)&&/buyer_quantity_coverage/i.test(migration),'Quantity fit is part of current match ranking');
must(/earliest_feasible_date asc/i.test(migration),'Timing is an explicit ranking tiebreaker');
must(/sell_offer_id asc/i.test(migration)||/buy_order_id asc/i.test(migration),'F-27 deterministic final match tiebreaker exists');
must(copyIntegrity.includes('net economic room')&&copyIntegrity.includes('quantity coverage'),'F-26 user-facing match copy names the implemented ranking factors');
must(copyIntegrity.includes('one indicative route allowance')&&copyIntegrity.includes('not observed component costs'),'F-24 UI no longer claims an unimplemented observed cost decomposition');
must(/alter\s+view\s+public\.open_supply_view\s+set\s*\(security_invoker\s*=\s*true\)/i.test(viewSecurity),'Matching supply view uses SECURITY INVOKER');
must(/alter\s+view\s+public\.matching_candidates_view\s+set\s*\(security_invoker\s*=\s*true\)/i.test(viewSecurity),'Matching candidate view uses SECURITY INVOKER');
must(/revoke\s+all\s+on\s+table\s+public\.matching_candidates_view\s+from\s+public,\s*anon,\s*authenticated/i.test(viewSecurity),'Internal matching view has no direct browser grants');

// Seller/buyer trust symmetry and commercial-party settlement.
must(/Farmer verification is required before posting supply/i.test(migration),'F-13 farmer verification gate exists');
must(/Seller is not currently verified for new trades/i.test(migration),'Seller verification rechecked at trade formation');
must(/Buyer organization must record payment initiation/i.test(migration),'F-12 normal payment initiation belongs to buyer');
must(/Seller must confirm payment receipt/i.test(migration),'F-12 normal payment receipt confirmation belongs to seller');
must(/QC operators can record telemetry only for their own inspection records/i.test(migration),'F-21 QC telemetry ownership enforced');
must(/shipments_one_active_per_trade_idx/i.test(migration),'F-22 active shipment uniqueness has a DB backstop');

// Client trust: no automatic fake transaction seed and no signed-out fake matching.
must(!app.includes('demo-settlement-seed.js'),'F-14 demo settlement seed removed from production bootstrap');
must(app.includes('backend/v1-8-hardening.js'),'v1.8 trust guard is a required bootstrap module');
must(app.includes('backend/v1-8-final-hardening.js'),'Final v1.8 trust hardening is a required bootstrap module');
must(app.includes('backend/v1-8-copy-integrity.js'),'Economic copy-integrity guard is a required bootstrap module');
must(hardening.includes("event.target?.id!=='sellForm'")&&hardening.includes('guardSellSubmit'),'F-07 seller submit is guarded before legacy fallback');
must(hardening.includes("event.target?.id!=='buyerDemandForm'")&&hardening.includes('guardBuyerSubmit'),'Buyer submit cannot silently fall back to fake local matching');
must(hardening.includes('realMatchesOnly')&&hardening.includes('suppressLegacyTransactionalDemo'),'Legacy static transactional matches are suppressed');
must(finalHardening.includes('rewireDemandShortcut'),'F-11 Post demand shortcut is rewired to the real buyer workflow');
must(finalHardening.includes('installOperationalActionGuard'),'F-19 operational actions have client-side rapid-repeat protection');
must(finalHardening.includes('markSimulatedWidgets'),'F-17 static dashboard widgets receive per-widget simulated labels');
must(finalHardening.includes('warnOrphanSession'),'Orphan/incomplete authenticated profile receives an explicit warning');

// Bilingual and role-aware behavior.
must(hardening.includes("const LANG_KEY='agroPublicLang'"),'F-10 trading app shares persistent language preference');
must(hardening.includes('update_my_profile_preferences'),'Signed-in language preference can persist to profile');
must(hardening.includes('আপনি কী বিক্রি করতে চান?'),'Farmer-first Bangla home copy exists');
must(hardening.includes('Potato:t(\'potato\')')&&hardening.includes("Bogra:t('bogra')"),'F-09 farmer select values are localized');
must(hardening.includes("p.role==='farmer'")&&hardening.includes("showView('sell')"),'Farmer role routes to Sell Produce');
must(hardening.includes("p.role==='buyer'")&&hardening.includes("showView('demand')"),'Buyer role routes to Buyer Demand');
must(hardening.includes('localizeServerMessage'),'F-08 server errors pass through Bangla-safe localization');
must(finalHardening.includes("'Primary navigation','প্রধান নেভিগেশন'")&&finalHardening.includes("'Notifications','নোটিফিকেশন'"),'Accessibility labels localize with the selected language');

// Mobile/PWA/backend truthfulness.
const runtimeVersion=runtime.match(/buildVersion:\s*['\"]([^'\"]+)['\"]/)?.[1];
const cacheVersion=sw.match(/CACHE_NAME='agro-exchange-shell-v([^']+)'/)?.[1];
must(versionAtLeast(runtimeVersion,'1.8.1'),'Runtime retains the v1.8.1-or-later hardened build identity');
must(versionAtLeast(cacheVersion,'1.8.1'),'F-31 PWA cache namespace remains at v1.8.1 or later');
must(sw.includes('backend/v1-8-hardening.js')&&sw.includes('backend/v1-8-final-hardening.js')&&sw.includes('backend/v1-8-copy-integrity.js')&&!sw.includes('demo-settlement-seed.js'),'PWA shell contains trust/copy hardening and excludes demo seed');
must(finalHardening.includes('ax_build_check')&&finalHardening.includes("cache:'no-store'"),'F-31 stale installed client can detect a newer deployed build');
must(finalCss.includes('min-width:44px')&&finalCss.includes('min-height:44px'),'F-29 minimum touch-target safeguards exist');
must(finalCss.includes('100dvh'),'F-30 transactional sheets use dynamic viewport sizing safeguard');
must(health.includes("window.dispatchEvent(new CustomEvent('agro-backend-status'"),'Health module publishes real backend state');
must(pwa.includes("window.addEventListener('agro-backend-status'"),'F-32 PWA warning listens to backend reachability, not navigator.onLine alone');

if(errors.length){
  console.error('\nAgro-Exchange v1.8 forensic regression check FAILED\n');
  errors.forEach(e=>console.error(' - '+e));
  process.exit(1);
}
console.log('Agro-Exchange v1.8 forensic regression check PASSED');
pass.forEach(p=>console.log(' - '+p));
