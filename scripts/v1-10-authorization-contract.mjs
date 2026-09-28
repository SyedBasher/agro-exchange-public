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

if(errors.length){
  console.error('\nAgro-Exchange v1.10 authorization contract check FAILED\n');
  errors.forEach(e=>console.error(' - '+e));
  process.exit(1);
}
console.log('Agro-Exchange v1.10 authorization contract check PASSED');
pass.forEach(p=>console.log(' - '+p));
