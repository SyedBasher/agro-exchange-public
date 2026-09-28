(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const LANG_KEY='agroPublicLang';
  const ROLE_HOME_KEY='agroV18RoleHomeApplied';
  const DEMO_CLEANUP_KEY='agroV18LegacyDemoCleared';

  const copy={
    en:{
      chooseLanguage:'Choose your language',chooseLanguageSub:'You can change this later at any time.',
      bangla:'বাংলা',english:'English',sellQuestion:'What do you want to sell?',
      sellSub:'Tell us what you have. Agro-Exchange will look for compatible verified buyers.',
      chooseProduce:'Choose produce',signInRequired:'Sign in to use the shared Agro-Exchange market.',
      verificationPendingTitle:'Farmer verification pending',
      verificationPendingBody:'Your account is signed in. You can review the selling steps now. After pilot verification, you can publish supply and look for verified buyers.',
      verificationPublishLabel:'Verification required before publishing',
      verificationRequired:'Your farmer account must be verified before you can post supply.',
      buyerApprovalRequired:'An approved buyer account is required to post demand.',
      wrongRole:'This action is not available for your account role.',serviceUnavailable:'The live transaction service is not ready. Please refresh and try again.',
      realMatchesOnly:'Real matches appear here after a signed-in farmer posts supply or an approved buyer posts demand.',
      realDemandOnly:'Buyer demand on this operational screen comes from the shared database. Sign in to participate.',
      simulated:'SIMULATED',simMarket:'Simulated market board',simMarketSub:'Illustrative pilot market conditions — not live transaction data.',
      priceCompatible:'Price compatible',quantityAvailable:'Quantity available',dateCompatible:'Timing compatible',verifiedCounterparty:'Verified counterparty',
      profileIncomplete:'Your account setup is incomplete. Please contact the pilot administrator.',
      backendUnavailable:'Live database unavailable',offline:'Offline · live data unavailable',
      gradeA:'Grade A',gradeB:'Grade B',standard:'Standard',potato:'Potato',onion:'Onion',rice:'Rice',bogra:'Bogra',rangpur:'Rangpur',joypurhat:'Joypurhat',
      openMenu:'Open menu',notifications:'Notifications',primaryNavigation:'Primary navigation',marketTicker:'Market ticker',close:'Close'
    },
    bn:{
      chooseLanguage:'ভাষা নির্বাচন করুন',chooseLanguageSub:'পরে যেকোনো সময় ভাষা পরিবর্তন করতে পারবেন।',
      bangla:'বাংলা',english:'English',sellQuestion:'আপনি কী বিক্রি করতে চান?',
      sellSub:'আপনার পণ্যের তথ্য দিন। Agro-Exchange উপযুক্ত যাচাইকৃত ক্রেতা খুঁজবে।',
      chooseProduce:'পণ্য বেছে নিন',signInRequired:'শেয়ার্ড Agro-Exchange বাজার ব্যবহার করতে সাইন ইন করুন।',
      verificationPendingTitle:'কৃষক যাচাই অপেক্ষমাণ',
      verificationPendingBody:'আপনি সাইন ইন করেছেন। এখন বিক্রির ধাপগুলো দেখতে পারবেন। পাইলট যাচাই সম্পন্ন হলে সরবরাহ প্রকাশ করে যাচাইকৃত ক্রেতা খুঁজতে পারবেন।',
      verificationPublishLabel:'প্রকাশের আগে যাচাই প্রয়োজন',
      verificationRequired:'সরবরাহ পোস্ট করার আগে আপনার কৃষক অ্যাকাউন্ট যাচাই হতে হবে।',
      buyerApprovalRequired:'চাহিদা পোস্ট করতে অনুমোদিত ক্রেতা অ্যাকাউন্ট প্রয়োজন।',
      wrongRole:'আপনার অ্যাকাউন্টের ভূমিকা দিয়ে এই কাজটি করা যাবে না।',serviceUnavailable:'লাইভ লেনদেন সেবা প্রস্তুত নয়। পেজ রিফ্রেশ করে আবার চেষ্টা করুন।',
      realMatchesOnly:'সাইন ইন করা কৃষক সরবরাহ বা অনুমোদিত ক্রেতা চাহিদা পোস্ট করলে এখানে বাস্তব ম্যাচ দেখা যাবে।',
      realDemandOnly:'এই অপারেশনাল পাতার ক্রেতা চাহিদা শেয়ার্ড ডেটাবেজ থেকে আসে। অংশ নিতে সাইন ইন করুন।',
      simulated:'সিমুলেটেড',simMarket:'সিমুলেটেড বাজার বোর্ড',simMarketSub:'পাইলটের উদাহরণমূলক বাজার অবস্থা — লাইভ লেনদেন তথ্য নয়।',
      priceCompatible:'মূল্য সামঞ্জস্যপূর্ণ',quantityAvailable:'পরিমাণ পাওয়া যাবে',dateCompatible:'সময় সামঞ্জস্যপূর্ণ',verifiedCounterparty:'যাচাইকৃত পক্ষ',
      profileIncomplete:'আপনার অ্যাকাউন্ট সেটআপ সম্পূর্ণ নয়। পাইলট প্রশাসকের সঙ্গে যোগাযোগ করুন।',
      backendUnavailable:'লাইভ ডেটাবেজ পাওয়া যাচ্ছে না',offline:'অফলাইন · লাইভ তথ্য পাওয়া যাচ্ছে না',
      gradeA:'গ্রেড A',gradeB:'গ্রেড B',standard:'স্ট্যান্ডার্ড',potato:'আলু',onion:'পেঁয়াজ',rice:'চাল',bogra:'বগুড়া',rangpur:'রংপুর',joypurhat:'জয়পুরহাট',
      openMenu:'মেনু খুলুন',notifications:'নোটিফিকেশন',primaryNavigation:'প্রধান নেভিগেশন',marketTicker:'বাজার টিকার',close:'বন্ধ করুন'
    }
  };

  const backendErrors={
    'Authentication required':['Authentication required.','সাইন ইন করা প্রয়োজন।'],
    'Profile not found':['Your Agro-Exchange profile could not be found.','আপনার Agro-Exchange প্রোফাইল পাওয়া যায়নি।'],
    'No Agro-Exchange profile is linked to this account':['Your account setup is incomplete. Please contact the pilot administrator.','আপনার অ্যাকাউন্ট সেটআপ সম্পূর্ণ নয়। পাইলট প্রশাসকের সঙ্গে যোগাযোগ করুন।'],
    'Farmer verification is required before posting supply':['Farmer verification is required before posting supply.','সরবরাহ পোস্ট করার আগে কৃষক অ্যাকাউন্ট যাচাই প্রয়োজন।'],
    'Only verified buyer accounts can post demand':['Only an approved buyer account can post demand.','শুধু অনুমোদিত ক্রেতা অ্যাকাউন্ট থেকে চাহিদা পোস্ট করা যাবে।'],
    'Buyer account is not linked to a verified organization':['Your buyer account is not linked to an approved organization.','আপনার ক্রেতা অ্যাকাউন্ট কোনো অনুমোদিত প্রতিষ্ঠানের সঙ্গে যুক্ত নয়।'],
    'Quantity must be greater than zero':['Quantity must be greater than zero.','পরিমাণ শূন্যের বেশি হতে হবে।'],
    'Minimum price must be greater than zero':['Minimum price must be greater than zero.','সর্বনিম্ন মূল্য শূন্যের বেশি হতে হবে।'],
    'Target price must be greater than zero':['Target price must be greater than zero.','লক্ষ্যমূল্য শূন্যের বেশি হতে হবে।'],
    'Price must be greater than zero':['Price must be greater than zero.','মূল্য শূন্যের বেশি হতে হবে।'],
    'Availability date is required':['Availability date is required.','উপলব্ধতার তারিখ প্রয়োজন।'],
    'Availability date cannot be in the past':['Availability date cannot be in the past.','উপলব্ধতার তারিখ অতীতের হতে পারে না।'],
    'Delivery start date cannot be in the past':['Delivery start date cannot be in the past.','ডেলিভারি শুরুর তারিখ অতীতের হতে পারে না।'],
    'Grade is not valid for this commodity':['The selected grade is not valid for this commodity.','নির্বাচিত গ্রেডটি এই পণ্যের জন্য সঠিক নয়।'],
    'Buyer grade requirement is not confirmed by this sell offer':['The buyer requires a grade that this supply offer has not confirmed.','ক্রেতার চাওয়া গ্রেডটি এই সরবরাহ প্রস্তাবে নিশ্চিত করা হয়নি।'],
    'Seller is not currently verified for new trades':['The seller is not currently verified for new trades.','নতুন লেনদেনের জন্য বিক্রেতা বর্তমানে যাচাইকৃত নয়।'],
    'Buyer organization is not currently verified for new trades':['The buyer organization is not currently approved for new trades.','নতুন লেনদেনের জন্য ক্রেতা প্রতিষ্ঠান বর্তমানে অনুমোদিত নয়।'],
    'Payment amount exceeds remaining amount due':['Payment amount exceeds the remaining amount due.','পেমেন্টের পরিমাণ বাকি পাওনার চেয়ে বেশি।'],
    'Buyer organization must record payment initiation':['The buyer must record payment initiation.','পেমেন্ট পাঠানোর তথ্য ক্রেতাকেই রেকর্ড করতে হবে।'],
    'Seller must confirm payment receipt':['The seller must confirm receipt of payment.','পেমেন্ট পাওয়ার বিষয়টি বিক্রেতাকেই নিশ্চিত করতে হবে।'],
    'Resolve the active dispute before confirming payment':['Resolve the active dispute before confirming payment.','পেমেন্ট নিশ্চিত করার আগে চলমান বিরোধ নিষ্পত্তি করুন।']
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(key){return copy[lang()][key]||copy.en[key]||key;}
  function signedIn(){return Boolean(window.AgroAuth?.isSignedIn?.());}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}

  function currentSavedLanguage(){
    try{const v=localStorage.getItem(LANG_KEY);return v==='bn'||v==='en'?v:null;}catch{return null;}
  }

  function persistLanguage(value){
    if(value!=='bn'&&value!=='en')return;
    try{localStorage.setItem(LANG_KEY,value);}catch(_){/* non-fatal */}
    syncProfileLanguage(value);
    window.dispatchEvent(new CustomEvent('agro-language-changed',{detail:{language:value}}));
  }

  async function syncProfileLanguage(value){
    const token=window.AgroAuth?.getAccessToken?.()||'';
    if(!token||!cfg.supabaseUrl||!cfg.anonKey)return;
    try{
      await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/update_my_profile_preferences',{
        method:'POST',
        headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token,'Content-Type':'application/json'},
        body:JSON.stringify({p_display_name:null,p_preferred_language:value})
      });
    }catch(_){/* local preference remains authoritative for this device */}
  }

  function setMainLanguage(wanted){
    if(wanted!=='bn'&&wanted!=='en')return;
    if(lang()!==wanted)document.getElementById('langToggle')?.click();
    persistLanguage(wanted);
    setTimeout(refreshLanguageUi,0);
  }

  function languageChooser(){
    if(currentSavedLanguage()||document.getElementById('axLanguageChooser'))return;
    const layer=document.createElement('div');
    layer.id='axLanguageChooser';
    layer.className='ax-language-chooser';
    layer.innerHTML=`<section role="dialog" aria-modal="true" aria-labelledby="axLanguageTitle" class="ax-language-card">
      <div class="brand-name">Agro-Exchange</div>
      <h1 id="axLanguageTitle">ভাষা নির্বাচন করুন <span>·</span> Choose your language</h1>
      <p>পরে যেকোনো সময় ভাষা পরিবর্তন করতে পারবেন। · You can change this later at any time.</p>
      <div class="ax-language-actions"><button type="button" data-language="bn">বাংলা</button><button type="button" data-language="en">English</button></div>
    </section>`;
    document.body.appendChild(layer);
    layer.querySelectorAll('[data-language]').forEach(button=>button.addEventListener('click',()=>{
      setMainLanguage(button.dataset.language);layer.remove();
    }));
  }

  function applySavedLanguage(){
    const p=profile();
    const preferred=p?.preferred_language;
    const saved=currentSavedLanguage();
    const wanted=(preferred==='bn'||preferred==='en')?preferred:saved;
    if(wanted)setMainLanguage(wanted);else languageChooser();
  }

  function refreshSelectOptions(){
    const labels={Potato:t('potato'),Onion:t('onion'),Rice:t('rice'),'Grade A':t('gradeA'),'Grade B':t('gradeB'),Standard:t('standard'),Bogra:t('bogra'),Rangpur:t('rangpur'),Joypurhat:t('joypurhat')};
    document.querySelectorAll('#sellForm option,#overviewCommodityFilter option,#marketCommodityFilter option,#marketOriginFilter option').forEach(option=>{
      const key=option.value||option.textContent.trim();if(labels[key])option.textContent=labels[key];
    });
  }

  function refreshAria(){
    const pairs=[['#mobileMenu','openMenu'],['.top-actions .icon-button','notifications'],['.sidebar','primaryNavigation'],['.market-ticker','marketTicker'],['.auth-close','close'],['.trade-close','close'],['.qc-close','close'],['.log-close','close'],['.set-close','close'],['.dsp-close','close'],['.admin-close','close']];
    pairs.forEach(([selector,key])=>document.querySelectorAll(selector).forEach(el=>el.setAttribute('aria-label',t(key))));
  }

  function addSimulationLabel(element){
    if(!element||element.querySelector(':scope > .ax-sim-chip'))return;
    const chip=document.createElement('span');chip.className='ax-sim-chip';chip.textContent=t('simulated');element.prepend(chip);
  }

  function labelSimulatedWidgets(){
    document.querySelectorAll('#overview .metric-card,#overview .opportunity-card,#overview .insight-card,#intelligence .card').forEach(addSimulationLabel);
    const marketTitle=document.querySelector('[data-i18n="live_markets"]');
    const marketSub=document.querySelector('[data-i18n="live_markets_sub"]');
    if(marketTitle)marketTitle.textContent=t('simMarket');
    if(marketSub)marketSub.textContent=t('simMarketSub');
    document.querySelectorAll('.ax-sim-chip').forEach(el=>el.textContent=t('simulated'));
  }

  function injectFarmerChooser(){
    const form=document.getElementById('sellForm');
    if(!form||document.getElementById('axCommodityChooser'))return;
    const commoditySelect=form.querySelector('select[name="commodity"]');if(!commoditySelect)return;
    const chooser=document.createElement('div');chooser.id='axCommodityChooser';chooser.className='ax-commodity-chooser';
    chooser.innerHTML=`<strong class="ax-commodity-label">${t('chooseProduce')}</strong><div class="ax-commodity-buttons"><button type="button" data-commodity="Potato"></button><button type="button" data-commodity="Onion"></button><button type="button" data-commodity="Rice"></button></div>`;
    form.insertBefore(chooser,form.firstElementChild?.nextSibling||form.firstChild);
    chooser.querySelectorAll('[data-commodity]').forEach(btn=>btn.addEventListener('click',()=>{
      commoditySelect.value=btn.dataset.commodity;commoditySelect.dispatchEvent(new Event('change',{bubbles:true}));
      chooser.querySelectorAll('button').forEach(x=>x.classList.toggle('selected',x===btn));
    }));
    refreshFarmerChooser();
  }

  function refreshFarmerChooser(){
    const heading=document.querySelector('#sell .page-heading');
    const title=heading?.querySelector('h1');const sub=heading?.querySelector('p');
    if(title)title.textContent=t('sellQuestion');if(sub)sub.textContent=t('sellSub');
    const label=document.querySelector('.ax-commodity-label');if(label)label.textContent=t('chooseProduce');
    document.querySelectorAll('#axCommodityChooser [data-commodity]').forEach(btn=>{const map={Potato:'potato',Onion:'onion',Rice:'rice'};btn.textContent=t(map[btn.dataset.commodity]);});
  }

  function refreshFarmerVerificationNotice(){
    const form=document.getElementById('sellForm');if(!form)return;
    let notice=document.getElementById('axFarmerVerificationNotice');
    const p=profile();
    const shouldShow=Boolean(signedIn()&&p?.role==='farmer'&&!p.verified);
    const submit=form.querySelector('button[type="submit"]');
    if(!shouldShow){
      notice?.remove();
      if(submit?.dataset.axOriginalLabel){
        submit.disabled=false;
        submit.removeAttribute('aria-disabled');
        submit.classList.remove('ax-verification-disabled');
        submit.textContent=submit.dataset.axOriginalLabel;
        delete submit.dataset.axOriginalLabel;
      }
      return;
    }
    if(!notice){
      notice=document.createElement('div');
      notice.id='axFarmerVerificationNotice';
      notice.className='ax-farmer-verification';
      notice.setAttribute('role','status');
      form.insertBefore(notice,form.firstChild);
    }
    notice.innerHTML=`<strong>${t('verificationPendingTitle')}</strong><span>${t('verificationPendingBody')}</span>`;

    if(submit){
      if(shouldShow){
        if(!submit.dataset.axOriginalLabel)submit.dataset.axOriginalLabel=submit.textContent.trim();
        submit.disabled=true;
        submit.setAttribute('aria-disabled','true');
        submit.classList.add('ax-verification-disabled');
        submit.textContent=t('verificationPublishLabel');
      }else if(submit.dataset.axOriginalLabel){
        submit.disabled=false;
        submit.removeAttribute('aria-disabled');
        submit.classList.remove('ax-verification-disabled');
        submit.textContent=submit.dataset.axOriginalLabel;
        delete submit.dataset.axOriginalLabel;
      }
    }
  }

  function refreshRoleNavigation(){
    const p=profile();
    const endUser=Boolean(signedIn()&&(p?.role==='farmer'||p?.role==='buyer'));
    document.body.classList.toggle('ax-end-user-role',endUser);
  }

  function replaceDeadDemandButton(){
    const original=document.querySelector('#demand .page-heading .heading-actions button[data-action="prototype"]');
    if(!original)return;
    const button=original.cloneNode(true);button.removeAttribute('data-action');button.dataset.axRewired='true';original.replaceWith(button);
    button.addEventListener('click',()=>{if(typeof window.showView==='function')window.showView('demand');document.getElementById('buyerDemandForm')?.querySelector('select,input,button')?.focus();});
  }

  function cleanupLegacyDemoState(){
    try{
      if(localStorage.getItem(DEMO_CLEANUP_KEY)==='1')return;
      ['agro_exchange_sell_offers_v1','agro_exchange_buy_orders_v1','agro_exchange_trade_confirmations_v1','agro_exchange_qc_records_v1','agro_exchange_shipments_v1','agro_exchange_settlement_v1','agro_exchange_disputes_v1'].forEach(key=>localStorage.removeItem(key));
      localStorage.setItem(DEMO_CLEANUP_KEY,'1');
    }catch(_){/* non-fatal */}
  }

  function ensureOperationalEmptyState(containerId,messageKey){
    const target=document.getElementById(containerId);if(!target)return;
    target.querySelectorAll('.match-row,.buyer-card').forEach(el=>el.remove());
    let note=target.querySelector('.ax-live-only-note');
    const hasReal=Boolean(target.querySelector('#latestPersistentOffer,.buyer-workflow-results > *'));
    if(hasReal){if(note)note.remove();return;}
    if(!note){note=document.createElement('div');note.className='card ax-live-only-note';target.appendChild(note);}
    const message=t(messageKey);if(note.textContent!==message)note.textContent=message;
  }

  function suppressLegacyTransactionalDemo(){
    ensureOperationalEmptyState('matchList','realMatchesOnly');
    ensureOperationalEmptyState('buyerDemandGrid','realDemandOnly');
  }

  function reasonMarkup(){return `<span>✓ ${t('priceCompatible')}</span><span>✓ ${t('quantityAvailable')}</span><span>✓ ${t('dateCompatible')}</span><span>✓ ${t('verifiedCounterparty')}</span>`;}
  function addMatchReasons(){
    document.querySelectorAll('.persistent-match-row,.buyer-match-row').forEach(row=>{
      let reasons=row.querySelector('.ax-match-reasons');
      if(!reasons){reasons=document.createElement('div');reasons.className='ax-match-reasons';row.appendChild(reasons);}
      if(reasons.dataset.lang!==lang()){
        reasons.dataset.lang=lang();
        reasons.innerHTML=reasonMarkup();
      }
    });
  }

  function localizeServerMessage(raw){
    const text=String(raw||'').trim();if(lang()==='en')return text;
    for(const [needle,pair] of Object.entries(backendErrors))if(text.includes(needle))return pair[1];
    if(!text)return 'কাজটি সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।';
    console.warn('Untranslated backend message suppressed from Bangla UI:',text);
    return 'কাজটি সম্পন্ন করা যায়নি। আবার চেষ্টা করুন।';
  }

  function wrapToast(){
    if(typeof window.toast!=='function'||window.toast.__axV18)return;
    const original=window.toast;const wrapped=function(message){return original(localizeServerMessage(message));};wrapped.__axV18=true;window.toast=wrapped;
  }

  function observeAuthError(){
    const node=document.getElementById('authError');if(!node||node.dataset.axObserved)return;
    node.dataset.axObserved='1';
    new MutationObserver(()=>{if(lang()==='bn'&&node.textContent.trim())node.textContent=localizeServerMessage(node.textContent);}).observe(node,{childList:true,subtree:true,characterData:true});
  }

  function openAuthWith(message){if(typeof window.toast==='function')window.toast(message);window.AgroAuth?.open?.();}

  function guardSellSubmit(event){
    if(event.target?.id!=='sellForm')return;
    const p=profile();
    if(!signedIn()){event.preventDefault();event.stopImmediatePropagation();openAuthWith(t('signInRequired'));return;}
    if(!p){event.preventDefault();event.stopImmediatePropagation();window.toast?.(t('profileIncomplete'));return;}
    if(!['farmer','admin'].includes(p.role)){event.preventDefault();event.stopImmediatePropagation();window.toast?.(t('wrongRole'));return;}
    if(p.role==='farmer'&&!p.verified){event.preventDefault();event.stopImmediatePropagation();window.toast?.(t('verificationRequired'));return;}
    if(!window.AgroPersistence?.remoteReady?.()){event.preventDefault();event.stopImmediatePropagation();window.toast?.(t('serviceUnavailable'));}
  }

  function guardBuyerSubmit(event){
    if(event.target?.id!=='buyerDemandForm')return;
    const p=profile();
    if(!signedIn()){event.preventDefault();event.stopImmediatePropagation();openAuthWith(t('signInRequired'));return;}
    if(!p||p.role!=='buyer'||!p.verified){event.preventDefault();event.stopImmediatePropagation();window.toast?.(t('buyerApprovalRequired'));return;}
    if(!window.AgroBuyerWorkflow?.remoteReady?.()){event.preventDefault();event.stopImmediatePropagation();window.toast?.(t('serviceUnavailable'));}
  }

  function applyRoleHome(){
    if(!signedIn())return false;
    const p=profile();if(!p)return false;
    const marker=String(p.id||p.role);
    if(sessionStorage.getItem(ROLE_HOME_KEY)===marker)return true;
    let routed=false;
    if(p.role==='farmer'&&typeof window.showView==='function'){window.showView('sell');routed=true;}
    else if(p.role==='buyer'&&typeof window.showView==='function'){window.showView('demand');routed=true;}
    if(routed)sessionStorage.setItem(ROLE_HOME_KEY,marker);
    refreshFarmerVerificationNotice();
    return routed;
  }

  function debounceHighStakesActions(event){
    const button=event.target?.closest?.('button');if(!button)return;
    if(!button.closest('.settlement-workspace,.dispute-workspace,.logistics-workspace,.set-sheet,.dsp-sheet,.log-sheet'))return;
    if(button.dataset.axBusyLock==='1'){event.preventDefault();event.stopImmediatePropagation();return;}
    button.dataset.axBusyLock='1';setTimeout(()=>delete button.dataset.axBusyLock,1800);
  }

  function refreshLanguageUi(){
    refreshSelectOptions();refreshAria();refreshFarmerChooser();refreshFarmerVerificationNotice();refreshRoleNavigation();labelSimulatedWidgets();suppressLegacyTransactionalDemo();addMatchReasons();observeAuthError();
    const footer=document.querySelector('.sidebar-footer span');if(footer)footer.textContent='v1.10 controlled staging';
  }

  function reportModuleFailure(src,error){
    console.error('Agro-Exchange module failed to load:',src,error);
    let banner=document.getElementById('axModuleFailure');
    if(!banner){banner=document.createElement('div');banner.id='axModuleFailure';banner.className='ax-module-failure';document.body.prepend(banner);}
    banner.textContent=t('serviceUnavailable')+' ['+src+']';
  }

  function init(){
    cleanupLegacyDemoState();wrapToast();applySavedLanguage();injectFarmerChooser();replaceDeadDemandButton();refreshLanguageUi();
    document.addEventListener('submit',guardSellSubmit,true);
    document.addEventListener('submit',guardBuyerSubmit,true);
    document.addEventListener('click',debounceHighStakesActions,true);
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{persistLanguage(lang());refreshLanguageUi();},0));
    window.addEventListener('agro-auth-changed',()=>setTimeout(()=>{applySavedLanguage();applyRoleHome();refreshLanguageUi();},350));
    window.addEventListener('agro-profile-ready',()=>setTimeout(()=>{applySavedLanguage();applyRoleHome();refreshLanguageUi();},0));

    let observerPending=false;
    const observer=new MutationObserver(()=>{
      if(observerPending)return;observerPending=true;
      queueMicrotask(()=>{observerPending=false;suppressLegacyTransactionalDemo();addMatchReasons();});
    });
    const matches=document.getElementById('matchList');if(matches)observer.observe(matches,{childList:true,subtree:true});
    const demand=document.getElementById('buyerDemandGrid');if(demand)observer.observe(demand,{childList:true,subtree:true});

    [900,2000,4000].forEach(delay=>setTimeout(()=>{applySavedLanguage();applyRoleHome();refreshLanguageUi();},delay));
  }

  window.AgroV18={t,lang,localizeServerMessage,reportModuleFailure,refresh:refreshLanguageUi,applyRoleHome};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
