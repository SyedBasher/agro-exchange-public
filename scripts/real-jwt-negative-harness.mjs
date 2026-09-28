#!/usr/bin/env node

/**
 * Agro-Exchange real-JWT negative authorization harness.
 *
 * This script never creates users, promotes roles, or uses service-role credentials.
 * It requires a real staging access token supplied at runtime and only exercises
 * role-denied RPC paths that should fail before any write can occur.
 */

const base=String(process.env.AGRO_SUPABASE_URL||'').replace(/\/$/,'');
const key=String(process.env.AGRO_SUPABASE_PUBLISHABLE_KEY||'');
const token=String(process.env.AGRO_TEST_ACCESS_TOKEN||'');
const expectedRole=String(process.env.AGRO_TEST_EXPECTED_ROLE||'').trim();
const expectedVerifiedRaw=String(process.env.AGRO_TEST_EXPECTED_VERIFIED||'').trim().toLowerCase();

function fail(message){
  console.error('FAIL: '+message);
  process.exit(1);
}
function pass(message){console.log('PASS: '+message);}
function requireEnv(name,value){if(!value)fail(name+' is required');}
function expectedVerified(){
  if(expectedVerifiedRaw==='true')return true;
  if(expectedVerifiedRaw==='false')return false;
  return null;
}
async function request(path,options={}){
  const response=await fetch(base+path,{
    ...options,
    headers:{
      apikey:key,
      Authorization:'Bearer '+token,
      'Content-Type':'application/json',
      ...(options.headers||{})
    }
  });
  const text=await response.text();
  let data=null;
  try{data=text?JSON.parse(text):null;}catch{data={message:text};}
  return {response,data,text};
}
function errorText(result){
  const d=result.data||{};
  return String(d.message||d.error_description||d.error||d.hint||result.text||'');
}
async function expectRpcDenied(name,body,needle){
  const result=await request('/rest/v1/rpc/'+name,{method:'POST',body:JSON.stringify(body)});
  if(result.response.ok){
    fail(name+' unexpectedly succeeded; negative authorization boundary failed');
  }
  const message=errorText(result);
  if(!message.includes(needle)){
    fail(name+' failed for an unexpected reason: '+message);
  }
  pass(name+' denied as expected: '+needle);
}

requireEnv('AGRO_SUPABASE_URL',base);
requireEnv('AGRO_SUPABASE_PUBLISHABLE_KEY',key);
requireEnv('AGRO_TEST_ACCESS_TOKEN',token);
requireEnv('AGRO_TEST_EXPECTED_ROLE',expectedRole);

const userResult=await request('/auth/v1/user');
if(!userResult.response.ok)fail('real JWT was not accepted by Supabase Auth');
const user=userResult.data;
if(!user?.id)fail('authenticated user id was not returned');
pass('real JWT accepted by Supabase Auth');

const profileResult=await request('/rest/v1/profiles?select=id,role,verified&limit=1');
if(!profileResult.response.ok)fail('profile lookup failed: '+errorText(profileResult));
const profile=Array.isArray(profileResult.data)?profileResult.data[0]:null;
if(!profile)fail('no RLS-visible Agro-Exchange profile is linked to this JWT');
if(profile.role!==expectedRole)fail('expected role '+expectedRole+' but JWT profile is '+profile.role);

const expected=expectedVerified();
if(expected!==null&&Boolean(profile.verified)!==expected){
  fail('expected verified='+expected+' but profile returned verified='+Boolean(profile.verified));
}
pass('JWT is linked to expected '+profile.role+' profile');

const future=new Date(Date.now()+3*86400000).toISOString().slice(0,10);

if(profile.role==='farmer'&&!profile.verified){
  await expectRpcDenied('post_sell_offer',{
    p_commodity_code:'POTATO',
    p_grade_code:null,
    p_origin_district:'Bogra',
    p_quantity_kg:1,
    p_minimum_price:1,
    p_available_from:future,
    p_fulfilment_preference:'collection_base'
  },'Farmer verification is required before posting supply');

  await expectRpcDenied('post_buy_order',{
    p_commodity_code:'POTATO',
    p_grade_code:null,
    p_destination_district:'Dhaka',
    p_quantity_kg:1,
    p_target_price:1,
    p_delivery_from:future,
    p_delivery_until:future
  },'Only verified buyer accounts can post demand');
}else if(profile.role==='farmer'){
  await expectRpcDenied('post_buy_order',{
    p_commodity_code:'POTATO',
    p_grade_code:null,
    p_destination_district:'Dhaka',
    p_quantity_kg:1,
    p_target_price:1,
    p_delivery_from:future,
    p_delivery_until:future
  },'Only verified buyer accounts can post demand');
}else if(profile.role==='buyer'){
  if(!profile.verified)fail('buyer profile must be verified before buyer JWT readiness can pass');
  const myOrders=await request('/rest/v1/rpc/get_my_buy_orders',{method:'POST',body:'{}'});
  if(!myOrders.response.ok)fail('buyer read path failed: '+errorText(myOrders));
  pass('verified buyer can access own demand workflow');

  await expectRpcDenied('post_sell_offer',{
    p_commodity_code:'POTATO',
    p_grade_code:null,
    p_origin_district:'Bogra',
    p_quantity_kg:1,
    p_minimum_price:1,
    p_available_from:future,
    p_fulfilment_preference:'collection_base'
  },'Only farmer accounts can post supply in this workflow');
}else{
  console.log('INFO: identity/RLS preflight passed. No mutation-free negative RPC is yet defined for role '+profile.role+'.');
}

console.log('Real-JWT negative authorization harness PASSED');
