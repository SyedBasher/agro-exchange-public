import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const read=rel=>fs.readFileSync(path.join(root,rel),'utf8');
const errors=[];const pass=[];
function must(ok,msg){(ok?pass:errors).push(msg);}
function versionAtLeast(actual,minimum){
  const a=String(actual||'').split('.').map(Number),m=String(minimum||'').split('.').map(Number);
  for(let i=0;i<Math.max(a.length,m.length);i++){const av=a[i]||0,mv=m[i]||0;if(av>mv)return true;if(av<mv)return false;}
  return true;
}

const liveness=read('database/transaction_liveness_v1_9.sql');
const followup=read('database/transaction_liveness_v1_9_followup.sql');
const commercial=read('database/commercial_integrity_v1_9.sql');
const ops=read('backend/v1-9-operations.js');
const pilot=read('backend/pilot-readiness.js');
const auth=read('backend/auth.js');
const app=read('app.js');
const sw=read('sw.js');
const runtime=read('backend/runtime-config.js');
const stale=read('backend/v1-8-final-hardening.js');

// Round-2 R2-01: QC rejection must have an explicit resume signal and fail closed.
must(liveness.includes("'qc_rejected'")&&liveness.includes("Cannot determine a safe resume state"),'R2-01 QC-rejection dispute resume is explicit and fail-closed');

// R2-02/R2-07/R2-14: lifecycle exits and expiry.
for(const fn of ['withdraw_sell_offer','withdraw_buy_order','amend_sell_offer','amend_buy_order','decline_trade_confirmation','cancel_shipment','restore_trade_inventory_after_cancel']){
  must(liveness.includes('function public.'+fn),'Lifecycle RPC exists: '+fn);
}
must(liveness.includes("available_until>=current_date")&&liveness.includes("delivery_until>=current_date"),'Expired listings are excluded from live open views');
must(liveness.includes('trade_confirmations_one_open_pair_idx'),'Open confirmation pairs are deduplicated');
must(commercial.includes('expire_stale_confirmation_before_insert_v1_9'),'Stale confirmations are expired before a replacement proposal');
must(commercial.includes("then 'expired'"),'Participant confirmation history reports effective expiry');

// R2-03/F2/F2b: confidential order book and defense in depth.
must(/revoke select on table public\.sell_offers, public\.buy_orders from anon, authenticated, public/i.test(liveness),'Reservation-price tables are not directly readable by browser roles');
must(/revoke insert, update, delete, truncate, references, trigger[\s\S]*on all tables in schema public[\s\S]*from anon, authenticated/i.test(liveness),'Broad browser DML/TRUNCATE grants are revoked');
must(liveness.includes('get_my_sell_offers')&&liveness.includes('get_my_buy_orders'),'Owners retain controlled access to their own listings');

// R2-04/R2-05: authority and explicit commercial adjustment.
must(commercial.includes('enforce_buyer_membership_integrity'),'Buyer memberships require eligible verified parties');
must(commercial.includes('revoke_buyer_membership_on_profile_change_v1_9'),'Demotion/unverification revokes buyer authority');
must(commercial.includes('revoke_buyer_memberships_on_org_change_v1_9'),'Organization unverification revokes buyer authority');
must(commercial.includes('admin_revoke_buyer_membership'),'Explicit admin membership revocation exists');
must(commercial.includes('Received quantity differs from the agreed quantity'),'Receipt quantity differences cannot silently change settlement');
must(commercial.includes('Verified buyer organization confirmation required'),'Normal receipt confirmation belongs to an eligible buyer, not admin');
must(commercial.includes('proposed_unit_price_bdt_per_kg>0'),'Adjusted unit price cannot be zero');

// F3/F4 / QC operational assignment.
must(liveness.includes('qc_operator_profile_id')&&liveness.includes('assign_trade_qc'),'QC assignment is explicit');
must(followup.includes("t.qc_operator_profile_id=v_profile.id"),'QC queue is scoped to assigned operator');
must(liveness.includes("split_part(storage.objects.name,'/',1)")&&liveness.includes('t.qc_operator_profile_id=p.id'),'QC evidence is trade-path and assignment scoped');
must(liveness.includes('(select auth.uid())'),'Touched storage policies use scalar auth.uid');

// Client liveness controls.
for(const marker of ['get_my_sell_offers','get_my_buy_orders','withdraw_sell_offer','decline_trade_confirmation','accept_trade_confirmation','assign_trade_qc','cancel_shipment']){
  must(ops.includes(marker),'v1.9 client wires '+marker);
}
must(ops.includes("c.value==='Rice'")&&ops.includes("Grade A"),'Seller grade choices follow commodity-valid pilot grades');
must(!pilot.includes("catch(err){state=d;render()"),'Live pilot-readiness does not fail open to demo metrics');
must(pilot.includes("unavailable:'Live data unavailable"),'Live pilot-readiness has an explicit unavailable state');
must(!auth.includes('Configure the Twilio provider in Supabase'),'Auth UI does not expose provider configuration internals');
must(auth.includes('rebuildModalForLanguage'),'Auth modal can rebuild after language changes');

// PWA/stale-build safety.
const runtimeVersion=runtime.match(/buildVersion:\s*'([^']+)'/)?.[1];
const cacheVersion=sw.match(/CACHE_NAME='agro-exchange-shell-v([^']+)'/)?.[1];
must(versionAtLeast(runtimeVersion,'1.9'),'Runtime remains v1.9 or later');
must(versionAtLeast(cacheVersion,'1.9'),'Service-worker cache remains v1.9 or later');
must(sw.includes("url.searchParams.has('ax_build_check')")&&sw.includes("cache:'no-store'"),'Timestamped build probes are never cached');
must(stale.includes('dataset.axLatestBuild')&&stale.includes('Reload before transacting'),'Stale deployed builds block operational transaction actions');
must(app.includes('backend/v1-9-operations.js'),'v1.9 operations layer is loaded');
must(sw.includes('backend/v1-9-operations.js')&&sw.includes('backend/v1-9-operations.css'),'v1.9 operations assets are in the PWA shell');

if(errors.length){
  console.error('\nAgro-Exchange v1.9 regression check FAILED\n');
  errors.forEach(e=>console.error(' - '+e));
  process.exit(1);
}
console.log('Agro-Exchange v1.9 regression check PASSED');
pass.forEach(p=>console.log(' - '+p));
