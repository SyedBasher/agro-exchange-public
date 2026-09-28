(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const ACCESS_KEY='agroExchangeAccessToken';
  const REFRESH_KEY='agroExchangeRefreshToken';
  const EXPIRY_KEY='agroExchangeAccessExpiry';
  let pendingAuth={channel:null,value:''};
  let currentUser=null;
  let currentProfile=null;

  const css=document.createElement('link');
  css.rel='stylesheet';
  css.href='backend/auth.css';
  document.head.appendChild(css);

  function base(){return String(cfg.supabaseUrl||'').replace(/\/$/,'');}
  function apiKey(){return cfg.anonKey||'';}
  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function msg(en,bn){return lang()==='bn'?bn:en;}
  function accessToken(){return cfg.accessToken||sessionStorage.getItem(ACCESS_KEY)||'';}
  function refreshToken(){return sessionStorage.getItem(REFRESH_KEY)||'';}

  function setSession(data){
    if(!data||!data.access_token)return;
    cfg.accessToken=data.access_token;
    sessionStorage.setItem(ACCESS_KEY,data.access_token);
    if(data.refresh_token)sessionStorage.setItem(REFRESH_KEY,data.refresh_token);
    const expiresAt=data.expires_at?Number(data.expires_at)*1000:Date.now()+(Number(data.expires_in||3600)*1000);
    sessionStorage.setItem(EXPIRY_KEY,String(expiresAt));
    // A fresh Auth session should receive role-aware home routing once.
    sessionStorage.removeItem('agroV18RoleHomeApplied');
    window.dispatchEvent(new CustomEvent('agro-auth-changed',{detail:{signedIn:true}}));
  }

  function clearSession(){
    cfg.accessToken='';
    sessionStorage.removeItem(ACCESS_KEY);
    sessionStorage.removeItem(REFRESH_KEY);
    sessionStorage.removeItem(EXPIRY_KEY);
    sessionStorage.removeItem('agroV18RoleHomeApplied');
    currentUser=null;
    currentProfile=null;
    window.dispatchEvent(new CustomEvent('agro-auth-changed',{detail:{signedIn:false}}));
  }

  async function request(path,options={}){
    const response=await fetch(base()+path,{
      ...options,
      headers:{
        apikey:apiKey(),
        'Content-Type':'application/json',
        ...(options.headers||{})
      }
    });
    const text=await response.text();
    let data=null;
    try{data=text?JSON.parse(text):null;}catch{data={message:text};}
    if(!response.ok){
      const err=new Error(data?.msg||data?.message||data?.error_description||data?.error||('Request failed: '+response.status));
      err.status=response.status;
      err.data=data;
      throw err;
    }
    return data;
  }

  function normalizePhone(raw){
    let v=String(raw||'').replace(/[\s()-]/g,'');
    if(/^01\d{9}$/.test(v))v='+88'+v;
    else if(/^8801\d{9}$/.test(v))v='+'+v;
    if(!/^\+\d{8,15}$/.test(v))throw new Error(msg('Enter a valid mobile number, for example +8801XXXXXXXXX.','সঠিক মোবাইল নম্বর দিন, যেমন +8801XXXXXXXXX।'));
    return v;
  }

  function normalizeEmail(raw){
    const v=String(raw||'').trim().toLowerCase();
    if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v))throw new Error(msg('Enter a valid email address.','সঠিক ইমেইল ঠিকানা দিন।'));
    return v;
  }

  async function sendPhoneOtp(phone){
    const value=normalizePhone(phone);
    pendingAuth={channel:'sms',value};
    await request('/auth/v1/otp',{method:'POST',body:JSON.stringify({phone:value})});
    return value;
  }

  async function sendEmailOtp(email){
    const value=normalizeEmail(email);
    pendingAuth={channel:'email',value};
    const redirectTo=location.origin+location.pathname;
    await request('/auth/v1/otp?redirect_to='+encodeURIComponent(redirectTo),{
      method:'POST',
      body:JSON.stringify({email:value,data:{preferred_language:lang()}})
    });
    return value;
  }

  async function verifyPendingOtp(code){
    const token=String(code||'').trim();
    if(!/^\d{6,10}$/.test(token))throw new Error(msg('Enter the one-time code you received.','আপনি যে একবার ব্যবহারযোগ্য কোড পেয়েছেন তা লিখুন।'));
    if(!pendingAuth.channel||!pendingAuth.value)throw new Error(msg('Request a sign-in code first.','প্রথমে সাইন-ইন কোড অনুরোধ করুন।'));
    const body=pendingAuth.channel==='email'
      ?{type:'email',email:pendingAuth.value,token}
      :{type:'sms',phone:pendingAuth.value,token};
    const data=await request('/auth/v1/verify',{method:'POST',body:JSON.stringify(body)});
    setSession(data);
    currentUser=data?.user||null;
    await loadProfile();
    updateAccountUi();
    return data;
  }

  async function consumeRedirectSession(){
    if(!location.hash||!location.hash.includes('access_token='))return false;
    const params=new URLSearchParams(location.hash.replace(/^#/,''));
    const access=params.get('access_token');
    if(!access)return false;
    setSession({
      access_token:access,
      refresh_token:params.get('refresh_token')||'',
      expires_in:Number(params.get('expires_in')||3600),
      token_type:params.get('token_type')||'bearer'
    });
    history.replaceState(null,'',location.pathname+location.search);
    await loadUser();
    if(currentUser)await loadProfile();
    updateAccountUi();
    if(typeof toast==='function')toast(msg('Signed in successfully.','সফলভাবে সাইন ইন হয়েছে।'));
    return true;
  }

  async function refreshSession(){
    const token=refreshToken();
    if(!token)return null;
    try{
      const data=await request('/auth/v1/token?grant_type=refresh_token',{
        method:'POST',body:JSON.stringify({refresh_token:token})
      });
      setSession(data);
      currentUser=data?.user||currentUser;
      return data;
    }catch(err){
      clearSession();
      return null;
    }
  }

  async function ensureFreshSession(){
    const expiry=Number(sessionStorage.getItem(EXPIRY_KEY)||0);
    if(accessToken()&&expiry>Date.now()+60000)return accessToken();
    if(refreshToken()){
      const refreshed=await refreshSession();
      if(refreshed)return accessToken();
    }
    return accessToken();
  }

  async function loadUser(){
    const token=await ensureFreshSession();
    if(!token)return null;
    try{
      currentUser=await request('/auth/v1/user',{headers:{Authorization:'Bearer '+token}});
      return currentUser;
    }catch(err){
      if(err.status===401&&refreshToken()){
        const refreshed=await refreshSession();
        if(refreshed)return loadUser();
      }
      clearSession();
      return null;
    }
  }

  async function loadProfile(){
    const token=accessToken();
    if(!token)return null;
    try{
      const rows=await request('/rest/v1/profiles?select=id,role,display_name,phone,preferred_language,verified&limit=1',{
        headers:{Authorization:'Bearer '+token}
      });
      currentProfile=Array.isArray(rows)?rows[0]||null:null;
      return currentProfile;
    }catch{return null;}
  }

  async function signOut(){
    const token=accessToken();
    try{
      if(token)await request('/auth/v1/logout',{method:'POST',headers:{Authorization:'Bearer '+token}});
    }catch(_){/* local cleanup still applies */}
    clearSession();
    closeModal();
    updateAccountUi();
  }

  function injectModal(){
    if(document.getElementById('authModal'))return;
    const modal=document.createElement('div');
    modal.id='authModal';
    modal.className='auth-modal';
    modal.setAttribute('aria-hidden','true');
    modal.innerHTML=`<div class="auth-backdrop" data-auth-close></div>
      <section class="auth-sheet" role="dialog" aria-modal="true" aria-labelledby="authTitle">
        <button class="auth-close" type="button" data-auth-close aria-label="Close">×</button>
        <div class="auth-brand">Agro-Exchange</div>
        <div id="authSignedOut">
          <h2 id="authTitle">${msg('Sign in','সাইন ইন করুন')}</h2>
          <p>${msg('Use mobile OTP, or email sign-in for controlled pilot testing.','মোবাইল OTP ব্যবহার করুন, অথবা নিয়ন্ত্রিত পাইলট পরীক্ষার জন্য ইমেইল সাইন-ইন ব্যবহার করুন।')}</p>
          <div class="auth-methods" role="tablist" aria-label="${msg('Sign-in method','সাইন-ইন পদ্ধতি')}">
            <button id="authUsePhone" class="auth-method is-active" type="button">${msg('Mobile OTP','মোবাইল OTP')}</button>
            <button id="authUseEmail" class="auth-method" type="button">${msg('Email','ইমেইল')}</button>
          </div>
          <form id="authPhoneForm">
            <label>${msg('Mobile number','মোবাইল নম্বর')}<input id="authPhone" inputmode="tel" autocomplete="tel" value="+880" placeholder="+8801XXXXXXXXX" required></label>
            <button class="auth-primary" type="submit">${msg('Send OTP','OTP পাঠান')}</button>
          </form>
          <form id="authEmailForm" class="auth-hidden">
            <label>${msg('Email address','ইমেইল ঠিকানা')}<input id="authEmail" type="email" inputmode="email" autocomplete="email" placeholder="name@example.com" required></label>
            <button class="auth-primary" type="submit">${msg('Send sign-in email','সাইন-ইন ইমেইল পাঠান')}</button>
            <small>${msg('Depending on the project email template, the message may contain a code or a one-time sign-in link.','প্রকল্পের ইমেইল টেমপ্লেট অনুযায়ী বার্তায় একটি কোড বা একবার ব্যবহারযোগ্য সাইন-ইন লিংক থাকতে পারে।')}</small>
          </form>
          <div id="authEmailSent" class="auth-hidden">
            <div class="auth-sent" id="authEmailSentTo"></div>
            <p>${msg('Open the email from Agro-Exchange and click the Sign in link. No code is required with the current staging email template.','Agro-Exchange থেকে আসা ইমেইলটি খুলে Sign in লিংকে ক্লিক করুন। বর্তমান স্টেজিং ইমেইল টেমপ্লেটে কোনো কোডের প্রয়োজন নেই।')}</p>
            <p><small>${msg('If you do not see the email, check Spam or Junk. The sign-in link can only be used once and expires shortly.','ইমেইলটি না দেখলে Spam বা Junk ফোল্ডার দেখুন। সাইন-ইন লিংকটি একবারই ব্যবহার করা যায় এবং অল্প সময়ের মধ্যে মেয়াদ শেষ হয়।')}</small></p>
            <button class="auth-secondary" id="authChangeEmail" type="button">${msg('Use another email','অন্য ইমেইল ব্যবহার করুন')}</button>
          </div>
          <form id="authOtpForm" class="auth-hidden">
            <div class="auth-sent" id="authSentTo"></div>
            <label>${msg('One-time code','একবার ব্যবহারযোগ্য কোড')}<input id="authOtp" inputmode="numeric" autocomplete="one-time-code" maxlength="10" placeholder="123456" required></label>
            <button class="auth-primary" type="submit">${msg('Verify and sign in','যাচাই করে সাইন ইন')}</button>
            <button class="auth-secondary" id="authChangeMethod" type="button">${msg('Use another sign-in method','অন্য সাইন-ইন পদ্ধতি ব্যবহার করুন')}</button>
          </form>
          <div class="auth-error" id="authError" role="alert"></div>
          <small>${msg('Pilot accounts are created as farmer accounts. Buyer and operational roles are approved separately.','পাইলট পর্যায়ে নতুন অ্যাকাউন্ট কৃষক অ্যাকাউন্ট হিসেবে তৈরি হবে। ক্রেতা ও অপারেশনাল ভূমিকা আলাদাভাবে অনুমোদন করা হবে।')}</small>
        </div>
        <div id="authSignedIn" class="auth-hidden">
          <h2>${msg('Account','অ্যাকাউন্ট')}</h2>
          <div class="auth-profile" id="authProfileSummary"></div>
          <button class="auth-secondary" id="authSignOut" type="button">${msg('Sign out','সাইন আউট')}</button>
        </div>
      </section>`;
    document.body.appendChild(modal);

    modal.querySelectorAll('[data-auth-close]').forEach(el=>el.addEventListener('click',closeModal));
    document.getElementById('authPhoneForm').addEventListener('submit',handlePhoneSubmit);
    document.getElementById('authEmailForm').addEventListener('submit',handleEmailSubmit);
    document.getElementById('authOtpForm').addEventListener('submit',handleOtpSubmit);
    document.getElementById('authUsePhone').addEventListener('click',()=>showAuthMethod('phone'));
    document.getElementById('authUseEmail').addEventListener('click',()=>showAuthMethod('email'));
    document.getElementById('authChangeMethod').addEventListener('click',()=>showAuthMethod('phone'));
    document.getElementById('authChangeEmail').addEventListener('click',()=>showAuthMethod('email'));
    document.getElementById('authSignOut').addEventListener('click',signOut);
  }

  function setError(text){
    const el=document.getElementById('authError');
    if(el)el.textContent=text||'';
  }

  function setBusy(form,busy){
    const btn=form?.querySelector('button[type="submit"]');
    if(btn){btn.disabled=busy;btn.classList.toggle('is-busy',busy);}
  }

  async function handlePhoneSubmit(e){
    e.preventDefault();
    setError('');
    setBusy(e.currentTarget,true);
    try{
      const phone=await sendPhoneOtp(document.getElementById('authPhone').value);
      document.getElementById('authSentTo').textContent=msg('Code sent to ','কোড পাঠানো হয়েছে ')+phone;
      document.getElementById('authPhoneForm').classList.add('auth-hidden');
      document.getElementById('authOtpForm').classList.remove('auth-hidden');
      document.getElementById('authOtp').focus();
    }catch(err){
      const raw=String(err.message||'');
      const provider=/sms|phone|provider|twilio/i.test(raw);
      setError(provider?msg('SMS sign-in is temporarily unavailable. Use Email for pilot testing.','SMS সাইন-ইন সাময়িকভাবে পাওয়া যাচ্ছে না। পাইলট পরীক্ষার জন্য ইমেইল ব্যবহার করুন।'):raw);
    }finally{setBusy(e.currentTarget,false);}
  }

  async function handleEmailSubmit(e){
    e.preventDefault();
    setError('');
    setBusy(e.currentTarget,true);
    try{
      const email=await sendEmailOtp(document.getElementById('authEmail').value);
      document.getElementById('authEmailSentTo').textContent=msg('Sign-in email sent to ','সাইন-ইন ইমেইল পাঠানো হয়েছে ')+email;
      document.getElementById('authEmailForm').classList.add('auth-hidden');
      document.getElementById('authPhoneForm').classList.add('auth-hidden');
      document.getElementById('authOtpForm').classList.add('auth-hidden');
      document.getElementById('authEmailSent').classList.remove('auth-hidden');
    }catch(err){
      setError(String(err.message||msg('Email sign-in is temporarily unavailable.','ইমেইল সাইন-ইন সাময়িকভাবে পাওয়া যাচ্ছে না।')));
    }finally{setBusy(e.currentTarget,false);}
  }

  async function handleOtpSubmit(e){
    e.preventDefault();
    setError('');
    setBusy(e.currentTarget,true);
    try{
      await verifyPendingOtp(document.getElementById('authOtp').value);
      closeModal();
      if(typeof toast==='function')toast(msg('Signed in successfully.','সফলভাবে সাইন ইন হয়েছে।'));
    }catch(err){setError(err.message||msg('The one-time code could not be verified.','একবার ব্যবহারযোগ্য কোড যাচাই করা যায়নি।'));}
    finally{setBusy(e.currentTarget,false);}
  }

  function showAuthMethod(method='phone'){
    pendingAuth={channel:null,value:''};
    setError('');
    document.getElementById('authOtpForm')?.classList.add('auth-hidden');
    document.getElementById('authEmailSent')?.classList.add('auth-hidden');
    document.getElementById('authPhoneForm')?.classList.toggle('auth-hidden',method!=='phone');
    document.getElementById('authEmailForm')?.classList.toggle('auth-hidden',method!=='email');
    document.getElementById('authUsePhone')?.classList.toggle('is-active',method==='phone');
    document.getElementById('authUseEmail')?.classList.toggle('is-active',method==='email');
  }

  function openModal(){
    injectModal();
    const modal=document.getElementById('authModal');
    const signedIn=document.getElementById('authSignedIn');
    const signedOut=document.getElementById('authSignedOut');
    if(accessToken()){
      signedOut.classList.add('auth-hidden');
      signedIn.classList.remove('auth-hidden');
      const summary=document.getElementById('authProfileSummary');
      const name=currentProfile?.display_name||msg('Farmer account','কৃষক অ্যাকাউন্ট');
      const contact=currentProfile?.phone||currentUser?.phone||currentUser?.email||'';
      const role=currentProfile?.role||'farmer';
      summary.innerHTML=`<strong>${escapeHtml(name)}</strong><span>${escapeHtml(contact)}</span><small>${escapeHtml(role)}</small>`;
    }else{
      signedIn.classList.add('auth-hidden');
      signedOut.classList.remove('auth-hidden');
      showAuthMethod(cfg.environment==='staging'?'email':'phone');
    }
    modal.classList.add('open');
    modal.setAttribute('aria-hidden','false');
  }

  function closeModal(){
    const modal=document.getElementById('authModal');
    if(!modal)return;
    modal.classList.remove('open');
    modal.setAttribute('aria-hidden','true');
  }

  function rebuildModalForLanguage(){
    const old=document.getElementById('authModal');
    const wasOpen=Boolean(old?.classList.contains('open'));
    old?.remove();
    injectModal();
    updateAccountUi();
    if(wasOpen)openModal();
  }

  function escapeHtml(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}

  function updateAccountUi(){
    const chip=document.querySelector('.account-chip');
    if(!chip)return;
    chip.setAttribute('role','button');
    chip.setAttribute('tabindex','0');
    chip.setAttribute('aria-label',accessToken()?msg('Open account','অ্যাকাউন্ট খুলুন'):msg('Sign in','সাইন ইন'));
    const strong=chip.querySelector('strong');
    const sub=chip.querySelector('span:not(.chevron)');
    if(accessToken()){
      if(strong)strong.textContent=currentProfile?.display_name||msg('Farmer account','কৃষক অ্যাকাউন্ট');
      if(sub)sub.textContent=currentProfile?.verified?msg('Verified farmer','যাচাইকৃত কৃষক'):msg('Farmer · pilot','কৃষক · পাইলট');
    }else{
      if(strong)strong.textContent=msg('Sign in','সাইন ইন');
      if(sub)sub.textContent=msg('OTP sign-in','OTP সাইন-ইন');
    }
  }

  async function init(){
    injectModal();
    await consumeRedirectSession();
    const chip=document.querySelector('.account-chip');
    if(chip){
      chip.addEventListener('click',openModal);
      chip.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();openModal();}});
    }
    if(accessToken()||refreshToken()){
      await loadUser();
      if(currentUser)await loadProfile();
    }
    updateAccountUi();
    window.addEventListener('agro-language-changed',()=>setTimeout(rebuildModalForLanguage,0));
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(rebuildModalForLanguage,0));
    setInterval(()=>{if(refreshToken())ensureFreshSession();},5*60*1000);
  }

  window.AgroAuth={open:openModal,signOut,getAccessToken:accessToken,refreshSession,isSignedIn:()=>Boolean(accessToken()),getProfile:()=>currentProfile};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
