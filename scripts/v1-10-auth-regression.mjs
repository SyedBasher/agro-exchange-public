import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const read=rel=>fs.readFileSync(path.join(root,rel),'utf8');
const errors=[];const pass=[];
function must(ok,msg){(ok?pass:errors).push(msg);}

const auth=read('backend/auth.js');
const css=read('backend/auth.css');
const runtime=read('backend/runtime-config.js');
const sw=read('sw.js');

must(auth.includes("sendEmailOtp"),'Email passwordless sign-in request exists');
must(auth.includes("redirect_to=")&&auth.includes("location.origin+location.pathname"),'Magic-link email returns to the active staging origin');
must(auth.includes("type:'email'")&&auth.includes("email:pendingAuth.value"),'Email OTP verification path exists');
must(auth.includes("consumeRedirectSession"),'Magic-link redirect session can be consumed');
must(auth.includes("location.hash.includes('access_token=')"),'Implicit magic-link fragment is detected');
must(auth.includes("history.replaceState"),'Auth tokens are removed from the address bar after redirect');
must(auth.includes("preferred_language:lang()"),'Email-created pilot profile carries language metadata');
must(auth.includes("cfg.environment==='staging'?'email':'phone'"),'Staging defaults to email while production can retain phone-first');
must(auth.includes("SMS sign-in is temporarily unavailable. Use Email for pilot testing."),'SMS provider failure offers the staging-safe fallback');
must(auth.includes("authUsePhone")&&auth.includes("authUseEmail"),'Bilingual sign-in method switch exists');
must(auth.includes("authEmailSent")&&auth.includes("No code is required with the current staging email template."),'Email staging flow explains magic-link sign-in instead of falsely requiring a code');
must(auth.includes("agroV18RoleHomeApplied"),'Fresh auth sessions reset the role-home routing latch');
must(!auth.includes("Configure the Twilio provider in Supabase"),'Provider internals are not exposed to end users');
must(css.includes('.auth-methods')&&css.includes('88dvh'),'Dual auth UI has mobile-safe styling');
must(/buildVersion:\s*['\"]1\.10['\"]/.test(runtime),'Runtime identifies v1.10');
must(sw.includes("CACHE_NAME='agro-exchange-shell-v1.10'"),'PWA cache identifies v1.10');

if(errors.length){
  console.error('\nAgro-Exchange v1.10 auth regression check FAILED\n');
  errors.forEach(e=>console.error(' - '+e));
  process.exit(1);
}
console.log('Agro-Exchange v1.10 auth regression check PASSED');
pass.forEach(p=>console.log(' - '+p));
