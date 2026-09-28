(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const OPERATIONAL_VIEWS=['sell','demand','matches','settlement','disputes','logistics','quality','qc','tradeConfirmations','trades'];
  const debounceTimers=new WeakMap();

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function msg(en,bn){return lang()==='bn'?bn:en;}
  function signedIn(){return Boolean(window.AgroAuth?.isSignedIn?.());}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function toastSafe(en,bn){if(typeof window.toast==='function')window.toast(msg(en,bn));}
  function setText(el,text){if(el&&el.textContent!==text)el.textContent=text;}

  function updateFooterVersion(){
    setText(document.querySelector('.sidebar-footer span'),'v'+(cfg.buildVersion||'1.8')+' · '+String(cfg.environment||'staging'));
  }

  function rewireDemandShortcut(){
    const heading=document.querySelector('#demand .page-heading .heading-actions');
    const old=heading?.querySelector('button');
    if(!old||old.dataset.axDemandWired==='1')return;
    const btn=old.cloneNode(true);
    btn.dataset.axDemandWired='1';
    btn.removeAttribute('data-action');
    old.replaceWith(btn);
    btn.addEventListener('click',()=>{
      if(!signedIn()){
        toastSafe('Sign in before posting buyer demand.','ক্রেতার চাহিদা পোস্ট করার আগে সাইন ইন করুন।');
        window.AgroAuth?.open?.();
        return;
      }
      const p=profile();
      if(!p){
        toastSafe('Your account setup is incomplete. Please contact the pilot administrator.','আপনার অ্যাকাউন্ট সেটআপ সম্পূর্ণ নয়। পাইলট প্রশাসকের সঙ্গে যোগাযোগ করুন।');
        return;
      }
      if(p.role!=='buyer'||!p.verified){
        toastSafe('An approved buyer account is required to post demand.','চাহিদা পোস্ট করতে অনুমোদিত ক্রেতা অ্যাকাউন্ট প্রয়োজন।');
        return;
      }
      const form=document.getElementById('buyerDemandForm');
      form?.scrollIntoView({behavior:'smooth',block:'start'});
      form?.querySelector('select,input,button')?.focus?.();
    });
  }

  function markSimulatedWidgets(){
    const label=msg('SIMULATED','সিমুলেটেড');
    document.querySelectorAll('.metric-card,.opportunity-card').forEach(card=>{
      let badge=card.querySelector('.ax-v18-sim-badge');
      if(!badge){badge=document.createElement('span');badge.className='ax-v18-sim-badge';card.prepend(badge);}
      setText(badge,label);
    });
    setText(document.querySelector('[data-i18n="live_markets"]'),msg('Simulated market board','সিমুলেটেড বাজার বোর্ড'));
    setText(document.querySelector('[data-i18n="live_markets_sub"]'),msg('Illustrative pilot market conditions — not live transaction data.','পাইলটের উদাহরণমূলক বাজার অবস্থা — লাইভ লেনদেন তথ্য নয়।'));
  }

  function addOperationalAuthGates(){
    for(const id of OPERATIONAL_VIEWS){
      const view=document.getElementById(id);
      if(!view)continue;
      let gate=view.querySelector(':scope > .ax-v18-auth-gate');
      const needsGate=!signedIn()||!profile();
      if(!needsGate){gate?.remove();continue;}
      if(!gate){
        gate=document.createElement('div');
        gate.className='ax-v18-auth-gate';
        const heading=view.querySelector('.page-heading');
        if(heading)heading.insertAdjacentElement('afterend',gate);else view.prepend(gate);
      }
      const html=signedIn()
        ? `<strong>${msg('Account setup incomplete','অ্যাকাউন্ট সেটআপ অসম্পূর্ণ')}</strong><span>${msg('This operational workflow stays read-only until your Agro-Exchange profile is available.','আপনার Agro-Exchange প্রোফাইল প্রস্তুত না হওয়া পর্যন্ত এই অপারেশনাল ওয়ার্কফ্লো শুধু দেখার জন্য থাকবে।')}</span>`
        : `<strong>${msg('Sign in required','সাইন ইন প্রয়োজন')}</strong><span>${msg('Operational transaction actions use the shared database. Local demonstration data are not actionable.','অপারেশনাল লেনদেন শেয়ার্ড ডেটাবেজ ব্যবহার করে। স্থানীয় ডেমো তথ্য দিয়ে লেনদেন করা যাবে না।')}</span>`;
      if(gate.innerHTML!==html)gate.innerHTML=html;
    }
  }

  function operationalViewFor(node){
    if(!node?.closest)return null;
    for(const id of OPERATIONAL_VIEWS){
      const view=node.closest('#'+id);
      if(view)return view;
    }
    return null;
  }

  function isDismissButton(btn){
    return /close|refresh|view/i.test([btn.id,btn.className,btn.getAttribute('aria-label'),btn.textContent].filter(Boolean).join(' '));
  }

  function installOperationalActionGuard(){
    if(document.documentElement.dataset.axActionGuard==='1')return;
    document.documentElement.dataset.axActionGuard='1';
    document.addEventListener('click',event=>{
      const btn=event.target.closest?.('button');
      if(!btn)return;
      const view=operationalViewFor(btn);
      if(!view||isDismissButton(btn))return;

      if(document.documentElement.dataset.axLatestBuild){
        event.preventDefault();event.stopImmediatePropagation();
        toastSafe('A newer Agro-Exchange build is available. Reload before transacting.','Agro-Exchange-এর নতুন সংস্করণ পাওয়া গেছে। লেনদেনের আগে রিলোড করুন।');
        return;
      }

      if(!signedIn()){
        event.preventDefault();event.stopImmediatePropagation();
        toastSafe('Sign in to perform this transaction action.','এই লেনদেনের কাজটি করতে সাইন ইন করুন।');
        window.AgroAuth?.open?.();
        return;
      }
      if(!profile()){
        event.preventDefault();event.stopImmediatePropagation();
        toastSafe('Your account setup is incomplete.','আপনার অ্যাকাউন্ট সেটআপ সম্পূর্ণ নয়।');
        return;
      }

      if(btn.dataset.axDebouncing==='1'){
        event.preventDefault();event.stopImmediatePropagation();
        return;
      }
      btn.dataset.axDebouncing='1';
      btn.classList.add('ax-v18-busy');
      btn.setAttribute('aria-disabled','true');
      const existing=debounceTimers.get(btn);if(existing)clearTimeout(existing);
      const timer=setTimeout(()=>{
        btn.dataset.axDebouncing='0';
        btn.classList.remove('ax-v18-busy');
        btn.removeAttribute('aria-disabled');
      },1800);
      debounceTimers.set(btn,timer);
    },true);

    document.addEventListener('submit',event=>{
      const form=event.target;
      if(!operationalViewFor(form))return;
      if(document.documentElement.dataset.axLatestBuild){
        event.preventDefault();event.stopImmediatePropagation();
        toastSafe('A newer Agro-Exchange build is available. Reload before transacting.','Agro-Exchange-এর নতুন সংস্করণ পাওয়া গেছে। লেনদেনের আগে রিলোড করুন।');
        return;
      }
      const submit=form.querySelector('button[type="submit"],input[type="submit"]');
      if(!submit)return;
      submit.classList.add('ax-v18-busy');
      submit.setAttribute('aria-disabled','true');
      setTimeout(()=>{submit.classList.remove('ax-v18-busy');submit.removeAttribute('aria-disabled');},5000);
    },true);
  }

  function warnOrphanSession(){
    if(!signedIn()||profile())return;
    if(document.documentElement.dataset.axOrphanWarned==='1')return;
    document.documentElement.dataset.axOrphanWarned='1';
    toastSafe(
      'You are signed in, but your Agro-Exchange profile is not available. Contact the pilot administrator before transacting.',
      'আপনি সাইন ইন করেছেন, কিন্তু আপনার Agro-Exchange প্রোফাইল পাওয়া যাচ্ছে না। লেনদেনের আগে পাইলট প্রশাসকের সঙ্গে যোগাযোগ করুন।'
    );
  }

  function showUpdateNotice(latest){
    if(document.getElementById('axVersionNotice'))return;
    const bar=document.createElement('div');
    bar.id='axVersionNotice';
    bar.className='ax-v18-version-notice';
    bar.innerHTML=`<span>${msg('A newer Agro-Exchange build is available. Reload before making a transaction.','Agro-Exchange-এর নতুন সংস্করণ পাওয়া গেছে। লেনদেনের আগে রিলোড করুন।')}</span><button type="button">${msg('Reload now','এখন রিলোড করুন')}</button>`;
    bar.querySelector('button').addEventListener('click',()=>location.reload());
    document.body.prepend(bar);
    document.documentElement.dataset.axLatestBuild=latest;
  }

  async function checkBuildFreshness(){
    if(!navigator.onLine||!cfg.buildVersion)return;
    try{
      const url='backend/runtime-config.js?ax_build_check='+Date.now();
      const res=await fetch(url,{cache:'no-store'});
      if(!res.ok)return;
      const text=await res.text();
      const match=text.match(/buildVersion\s*:\s*['\"]([^'\"]+)['\"]/);
      const latest=match?.[1];
      if(latest&&latest!==String(cfg.buildVersion))showUpdateNotice(latest);
    }catch(_){/* backend/network state is handled elsewhere */}
  }

  function localizeAccessibility(){
    document.querySelector('.sidebar')?.setAttribute('aria-label',msg('Primary navigation','প্রধান নেভিগেশন'));
    document.getElementById('mobileMenu')?.setAttribute('aria-label',msg('Open menu','মেনু খুলুন'));
    document.querySelector('.market-ticker')?.setAttribute('aria-label',msg('Market ticker','বাজার টিকার'));
    document.querySelector('.top-actions .icon-button')?.setAttribute('aria-label',msg('Notifications','নোটিফিকেশন'));
    document.querySelectorAll('.auth-close,.qc-close,.log-close,.set-close,.trade-close,.admin-close,.dsp-close').forEach(el=>el.setAttribute('aria-label',msg('Close','বন্ধ করুন')));
  }

  function refresh(){
    updateFooterVersion();
    rewireDemandShortcut();
    markSimulatedWidgets();
    addOperationalAuthGates();
    localizeAccessibility();
    setTimeout(warnOrphanSession,500);
  }

  function init(){
    installOperationalActionGuard();
    refresh();
    checkBuildFreshness();
    window.addEventListener('online',checkBuildFreshness);
    window.addEventListener('agro-auth-changed',()=>setTimeout(refresh,150));
    window.addEventListener('agro-language-changed',()=>setTimeout(refresh,0));
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(refresh,0));
    let queued=false;
    new MutationObserver(()=>{
      if(queued)return;queued=true;
      requestAnimationFrame(()=>{queued=false;refresh();});
    }).observe(document.body,{childList:true,subtree:true});
  }

  window.AgroV18Final={refresh,checkBuildFreshness};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
