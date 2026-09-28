import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const read=rel=>fs.readFileSync(path.join(root,rel),'utf8');
const errors=[];const pass=[];
function must(ok,msg){(ok?pass:errors).push(msg);}

const admin=read('database/admin_operations.sql');
const adminHardening=read('database/admin_operations_hardening.sql');
const buyer=read('database/buyer_verification_gate.sql');
const harness=read('scripts/real-jwt-negative-harness.mjs');
const readiness=read('database/real_jwt_account_readiness.sql');
const adminPreflight=read('database/first_admin_eligibility_preflight.sql');
const firstAdminBootstrap=read('database/pilot_admin_bootstrap_v1_9.sql');
const buyerReadiness=read('database/buyer_promotion_readiness.sql');

must(admin.includes('create or replace function public.require_admin_profile()'),'Admin guard helper exists');
must(admin.includes("if auth.uid() is null then raise exception 'Authentication required'"),'Admin guard requires authenticated identity');
must(admin.includes("v_profile.role<>'admin'"),'Admin guard requires admin profile role');
must(admin.includes('revoke all on function public.require_admin_profile() from public,anon,authenticated'),'Admin guard helper is not browser-callable');
must(admin.includes('v_admin:=public.require_admin_profile();'),'Admin RPCs delegate to the central admin guard');
must(adminHardening.includes('v_admin:=public.require_admin_profile();'),'Hardened profile-access workflow retains central admin guard');

must(buyer.includes("v_role<>'buyer'")&&buyer.includes('v_profile_verified'),'Buyer posting requires verified buyer role');
must(buyer.includes('org.verified=true'),'Buyer posting requires a verified buyer organization');
must(buyer.includes("if not (v_is_seller or v_is_buyer)"),'Trade confirmation requires seller or authorized buyer participation');

must(harness.includes("profile.role==='farmer'"),'Real-JWT harness includes farmer boundary tests');
must(harness.includes("profile.role==='buyer'"),'Real-JWT harness includes buyer boundary tests');
must(harness.includes('unexpectedly succeeded'),'Real-JWT harness fails closed on an unexpected RPC success');
must(!harness.includes('SERVICE_ROLE'),'Real-JWT harness contains no service-role dependency');
must(readiness.includes('auth_user_id is not null'),'Readiness gate distinguishes Auth-linked profiles from seeded profiles');
must(readiness.includes('core_farmer_buyer_admin_ready'),'Readiness gate requires independent farmer/buyer/admin coverage');
must(!/email|phone|token/i.test(readiness.replace(/^--.*$/gm,'')),'Readiness SQL does not expose participant contact or token fields');
must(adminPreflight.includes('linked_sequence >= 2'),'First-admin preflight excludes the original linked farmer');
must(adminPreflight.includes('linked_admins = 0'),'First-admin preflight fails closed once an admin exists');
must(adminPreflight.includes('first_admin_bootstrap_ready'),'First-admin preflight exposes a single readiness decision');
must(!/email|phone|raw_user_meta_data|access_token|refresh_token/i.test(adminPreflight.replace(/^--.*$/gm,'')),'First-admin preflight exposes no participant contact or auth-secret fields');
must(firstAdminBootstrap.includes("v_auth_users < 2 or v_linked_profiles < 2"),'Bootstrap itself requires a separate second Auth-linked account');
must(firstAdminBootstrap.includes("v_profile.id=v_original_profile_id"),'Bootstrap itself rejects the original linked farmer');
must(firstAdminBootstrap.includes("v_profile.role<>'farmer' or coalesce(v_profile.verified,false)"),'Bootstrap accepts only a newly linked unverified farmer candidate');
must(firstAdminBootstrap.includes("pg_advisory_xact_lock"),'Bootstrap serializes the one-time admin decision');
must(firstAdminBootstrap.includes("from public,anon,authenticated,service_role"),'Bootstrap remains unavailable to browser and service roles');
must(buyerReadiness.includes("linked_admins >= 1"),'Buyer promotion requires an independent linked admin');
must(buyerReadiness.includes("verified_orgs >= 1"),'Buyer promotion requires a verified buyer organization');
must(buyerReadiness.includes("linked_sequence >= 2"),'Buyer promotion excludes the original linked farmer');
must(buyerReadiness.includes("coalesce(l.verified,false)=false"),'Buyer promotion candidate must still be an unverified linked farmer');
must(buyerReadiness.includes("buyer_promotion_ready"),'Buyer promotion readiness emits a fail-closed decision');
must(harness.includes("get_my_buy_orders"),'Buyer JWT harness includes a positive own-demand read path');

if(errors.length){
  console.error('\nAgro-Exchange v1.10 authorization contract check FAILED\n');
  errors.forEach(e=>console.error(' - '+e));
  process.exit(1);
}
console.log('Agro-Exchange v1.10 authorization contract check PASSED');
pass.forEach(p=>console.log(' - '+p));
