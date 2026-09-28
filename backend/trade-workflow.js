(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const STORAGE_KEY='agro_exchange_trade_confirmations_v1';
  let activeCandidate=null;

  const copy={
    en:{
      kicker:'TRADE CONFIRMATION',title:'Turn a match into a trade',sub:'Review the commercial terms before either party commits. A trade becomes confirmed only after both sides accept the same terms.',
      demo:'Workflow test · device only',live:'Live authenticated workflow',pending:'Awaiting counterparty',confirmed:'Trade confirmed',
      create:'Create trade confirmation',acceptDemo:'Simulate counterparty acceptance',review:'Review terms',close:'Close',
      commodity:'Commodity',route:'Route',quantity:'Agreed quantity (kg)',price:'Agreed produce price (Tk/kg)',delivery:'Delivery due',payment:'Payment terms',qc:'QC required before dispatch',
      paymentDefault:'Payment after delivery confirmation',seller:'Seller',buyer:'Buyer',accepted:'Accepted',waiting:'Pending',reference:'Confirmation reference',tradeId:'Trade ID',
      notice:'This is a Digital Trade Confirmation for the pilot workflow. It is not yet presented as a legally binding commodity contract and it does not move money.',
      choose:'Choose a current match to prepare a confirmation.',localExample:'Use simulated Bogra potato → Dhaka match',saved:'Trade confirmation saved',counterpartyAccepted:'Counterparty acceptance simulated',
      noRemote:'No live trade confirmations yet.',myConfirmations:'My trade confirmations',expires:'Proposal window: 48 hours',
      invalidQty:'Quantity must be greater than zero.',invalidPrice:'Price is not valid.',
      simulated:'SIMULATED'
    },
    bn:{
      kicker:'লেনদেন নিশ্চিতকরণ',title:'ম্যাচ থেকে লেনদেন তৈরি করুন',sub:'কোনো পক্ষ সম্মতি দেওয়ার আগে বাণিজ্যিক শর্তগুলো দেখুন। একই শর্তে উভয় পক্ষ সম্মতি দিলে তবেই লেনদেন নিশ্চিত হবে।',
      demo:'ওয়ার্কফ্লো পরীক্ষা · শুধু ডিভাইসে',live:'লাইভ অথেন্টিকেটেড ওয়ার্কফ্লো',pending:'অন্য পক্ষের সম্মতির অপেক্ষায়',confirmed:'লেনদেন নিশ্চিত',
      create:'লেনদেন নিশ্চিতকরণ তৈরি করুন',acceptDemo:'অন্য পক্ষের সম্মতি সিমুলেট করুন',review:'শর্ত দেখুন',close:'বন্ধ করুন',
      commodity:'পণ্য',route:'রুট',quantity:'সম্মত পরিমাণ (কেজি)',price:'সম্মত পণ্যমূল্য (টাকা/কেজি)',delivery:'ডেলিভারির সময়সীমা',payment:'পেমেন্ট শর্ত',qc:'পাঠানোর আগে QC প্রয়োজন',
      paymentDefault:'ডেলিভারি নিশ্চিত হওয়ার পর পেমেন্ট',seller:'বিক্রেতা',buyer:'ক্রেতা',accepted:'সম্মত',waiting:'অপেক্ষমাণ',reference:'কনফার্মেশন রেফারেন্স',tradeId:'ট্রেড আইডি',
      notice:'এটি পাইলট ওয়ার্কফ্লোর Digital Trade Confirmation। এখনো এটিকে আইনগতভাবে বাধ্যতামূলক পণ্য চুক্তি হিসেবে দেখানো হচ্ছে না এবং এর মাধ্যমে অর্থ স্থানান্তর হয় না।',
      choose:'কনফার্মেশন তৈরির জন্য একটি বর্তমান ম্যাচ বেছে নিন।',localExample:'সিমুলেটেড বগুড়া আলু → ঢাকা ম্যাচ ব্যবহার করুন',saved:'লেনদেন নিশ্চিতকরণ সংরক্ষিত হয়েছে',counterpartyAccepted:'অন্য পক্ষের সম্মতি সিমুলেট করা হয়েছে',
      noRemote:'এখনো কোনো লাইভ লেনদেন নিশ্চিতকরণ নেই।',myConfirmations:'আমার লেনদেন নিশ্চিতকরণ',expires:'প্রস্তাবের সময়সীমা: ৪৮ ঘণ্টা',
      invalidQty:'পরিমাণ শূন্যের বেশি হতে হবে।',invalidPrice:'মূল্য সঠিক নয়।',
      simulated:'সিমুলেটেড'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token());}
  function uid(){return window.crypto?.randomUUID?.()||('local-'+Date.now()+'-'+Math.random().toString(16).slice(2));}
  function isoDate(offset){const d=new Date();d.setHours(12,0,0,0);d.setDate(d.getDate()+offset);return d.toISOString().slice(0,10);}
  function readLocal(){try{return JSON.parse(localStorage.getItem(STORAGE_KEY)||'[]');}catch{return [];}}
  function saveRows(rows){localStorage.setItem(STORAGE_KEY,JSON.stringify(rows.slice(0,50)));}
  function ref(){return 'AX-DEMO-'+new Date().toISOString().slice(0,10).replaceAll('-','')+'-'+Math.random().toString(36).slice(2,8).toUpperCase();}

  async function api(path,body){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+path,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body||{})});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  function demoCandidate(){
    return {source:'demo',commodity:'Potato',origin:'Bogra',destination:'Dhaka',quantityKg:5000,price:31.5,deliveryDue:isoDate(2),paymentTerms:t('paymentDefault'),qcRequired:true,sellerAccepted:true,buyerAccepted:false};
  }

  function inject(){
    if(document.getElementById('tradeWorkflow'))return;
    const matches=document.getElementById('matches');if(!matches)return;
    const card=document.createElement('section');card.id='tradeWorkflow';card.className='card trade-workflow-card';
    card.innerHTML=`<div class="trade-workflow-head"><div><div class="section-kicker" data-trade-key="kicker"></div><h2 data-trade-key="title"></h2><p data-trade-key="sub"></p></div><span id="tradeMode" class="trade-mode"></span></div>
      <div class="trade-workflow-body">
        <div class="trade-start"><p data-trade-key="choose"></p><button id="tradeDemoStart" class="button primary" type="button" data-trade-key="localExample"></button><small data-trade-key="notice"></small></div>
        <div id="tradeRecent" class="trade-recent"></div>
      </div>`;
    const heading=matches.querySelector('.page-heading');if(heading)heading.insertAdjacentElement('afterend',card);else matches.prepend(card);
    document.getElementById('tradeDemoStart').addEventListener('click',()=>open(demoCandidate()));
    localize();renderRecent();loadRemoteHistory();
  }

  function injectModal(){
    if(document.getElementById('tradeModal'))return;
    const m=document.createElement('div');m.id='tradeModal';m.className='trade-modal';m.setAttribute('aria-hidden','true');
    m.innerHTML=`<div class="trade-backdrop" data-trade-close></div><section class="trade-sheet" role="dialog" aria-modal="true" aria-labelledby="tradeModalTitle">
      <button class="trade-close" type="button" data-trade-close>×</button><div class="trade-brand">Agro-Exchange</div>
      <div class="section-kicker" data-trade-key="kicker"></div><h2 id="tradeModalTitle" data-trade-key="review"></h2>
      <div id="tradeCandidateSummary" class="trade-candidate-summary"></div>
      <form id="tradeForm" class="trade-form">
        <label><span data-trade-key="quantity"></span><input name="quantity" type="number" inputmode="decimal" min="1" step="1" required></label>
        <label><span data-trade-key="price"></span><input name="price" type="number" inputmode="decimal" min="0" step="0.1" required></label>
        <label><span data-trade-key="delivery"></span><input name="delivery" type="date" required></label>
        <label class="trade-wide"><span data-trade-key="payment"></span><input name="payment" type="text" maxlength="180"></label>
        <label class="trade-check trade-wide"><input name="qc" type="checkbox" checked><span data-trade-key="qc"></span></label>
        <div class="trade-wide trade-notice" data-trade-key="notice"></div>
        <button class="button primary trade-wide" type="submit" data-trade-key="create"></button>
      </form><div id="tradeResult"></div></section>`;
    document.body.appendChild(m);m.querySelectorAll('[data-trade-close]').forEach(x=>x.addEventListener('click',close));
    document.getElementById('tradeForm').addEventListener('submit',submit);
    localize();
  }

  function open(candidate){
    injectModal();activeCandidate=candidate||demoCandidate();
    const form=document.getElementById('tradeForm');
    form.elements.quantity.value=Math.round(activeCandidate.quantityKg||5000);
    form.elements.price.value=Number(activeCandidate.price||31.5).toFixed(1);
    form.elements.delivery.value=(activeCandidate.deliveryDue||isoDate(2)).slice(0,10);
    form.elements.payment.value=activeCandidate.paymentTerms||t('paymentDefault');
    form.elements.qc.checked=activeCandidate.qcRequired!==false;
    document.getElementById('tradeCandidateSummary').innerHTML=`<div><span>${t('commodity')}</span><strong>${esc(activeCandidate.commodity||'Potato')}</strong></div><div><span>${t('route')}</span><strong>${esc(activeCandidate.origin||'Bogra')} → ${esc(activeCandidate.destination||'Dhaka')}</strong></div>`;
    document.getElementById('tradeResult').innerHTML='';
    const m=document.getElementById('tradeModal');m.classList.add('open');m.setAttribute('aria-hidden','false');
  }
  function close(){const m=document.getElementById('tradeModal');if(m){m.classList.remove('open');m.setAttribute('aria-hidden','true');}}

  function buildLocal(candidate,fd){
    const quantity=Number(fd.get('quantity')),price=Number(fd.get('price'));
    if(!Number.isFinite(quantity)||quantity<=0)throw new Error(t('invalidQty'));
    if(!Number.isFinite(price)||price<0)throw new Error(t('invalidPrice'));
    return {id:uid(),reference:ref(),source:'demo',commodity:candidate.commodity||'Potato',origin:candidate.origin||'Bogra',destination:candidate.destination||'Dhaka',quantityKg:quantity,price,deliveryDue:String(fd.get('delivery')||''),paymentTerms:String(fd.get('payment')||''),qcRequired:fd.get('qc')==='on',sellerAccepted:candidate.sellerAccepted!==false,buyerAccepted:Boolean(candidate.buyerAccepted),status:candidate.buyerAccepted?'confirmed':'seller_accepted',tradeId:null,createdAt:new Date().toISOString()};
  }

  async function proposeLive(candidate,fd){
    if(!candidate.sellOfferId||!candidate.buyOrderId)throw new Error('A live match must include sellOfferId and buyOrderId.');
    const rows=await api('/rest/v1/rpc/propose_trade_confirmation',{p_sell_offer_id:candidate.sellOfferId,p_buy_order_id:candidate.buyOrderId,p_quantity_kg:Number(fd.get('quantity')),p_price_bdt_per_kg:Number(fd.get('price')),p_delivery_due_at:String(fd.get('delivery')||'')+'T12:00:00+06:00',p_payment_terms:String(fd.get('payment')||''),p_qc_required:fd.get('qc')==='on'});
    const r=Array.isArray(rows)?rows[0]:rows;
    return {id:r.confirmation_id,reference:r.confirmation_reference,source:'supabase',commodity:candidate.commodity,origin:candidate.origin,destination:candidate.destination,quantityKg:Number(fd.get('quantity')),price:Number(fd.get('price')),deliveryDue:String(fd.get('delivery')||''),paymentTerms:String(fd.get('payment')||''),qcRequired:fd.get('qc')==='on',sellerAccepted:Boolean(r.seller_accepted),buyerAccepted:Boolean(r.buyer_accepted),status:r.confirmation_status,tradeId:null,createdAt:new Date().toISOString()};
  }

  async function submit(e){
    e.preventDefault();const form=e.currentTarget;const btn=form.querySelector('button[type="submit"]');btn.disabled=true;
    try{
      const fd=new FormData(form);let row;
      if(activeCandidate?.source==='supabase'&&liveReady())row=await proposeLive(activeCandidate,fd);else row=buildLocal(activeCandidate||demoCandidate(),fd);
      if(row.source==='demo'){const rows=readLocal();rows.unshift(row);saveRows(rows);}
      renderResult(row);renderRecent();if(typeof toast==='function')toast(t('saved'));
    }catch(err){if(typeof toast==='function')toast(err.message||'Could not create trade confirmation.');}
    finally{btn.disabled=false;}
  }

  function renderResult(row){
    const target=document.getElementById('tradeResult');if(!target)return;
    target.innerHTML=`<div class="trade-confirmation-card"><div class="trade-confirmation-top"><div><small>${t('reference')}</small><strong>${esc(row.reference)}</strong></div><span class="${row.status==='confirmed'?'is-confirmed':'is-pending'}">${row.status==='confirmed'?t('confirmed'):t('pending')}</span></div>
      <div class="trade-acceptance"><div><span>${t('seller')}</span><strong>${row.sellerAccepted?'✓ '+t('accepted'):'○ '+t('waiting')}</strong></div><div><span>${t('buyer')}</span><strong>${row.buyerAccepted?'✓ '+t('accepted'):'○ '+t('waiting')}</strong></div></div>
      ${row.tradeId?`<div class="trade-id"><span>${t('tradeId')}</span><strong>${esc(row.tradeId)}</strong></div>`:''}
      ${row.source==='demo'&&row.status!=='confirmed'?`<button class="button secondary full" id="simulateAccept" type="button">${t('acceptDemo')}</button>`:''}
      <small>${t('expires')} · ${row.source==='demo'?t('simulated'):''}</small></div>`;
    document.getElementById('simulateAccept')?.addEventListener('click',()=>simulateAcceptance(row.id));
  }

  function simulateAcceptance(id){
    const rows=readLocal();const row=rows.find(x=>x.id===id);if(!row)return;
    row.buyerAccepted=true;row.status='confirmed';row.tradeId='TR-DEMO-'+Math.random().toString(36).slice(2,10).toUpperCase();row.confirmedAt=new Date().toISOString();saveRows(rows);renderResult(row);renderRecent();if(typeof toast==='function')toast(t('counterpartyAccepted'));
  }

  function renderRecent(remoteRows){
    const target=document.getElementById('tradeRecent');if(!target)return;
    const local=readLocal();const rows=remoteRows||local;
    if(!rows.length){target.innerHTML='';return;}
    target.innerHTML=`<h3>${t('myConfirmations')}</h3><div class="trade-recent-list">${rows.slice(0,5).map(r=>`<article><div><strong>${esc(r.confirmation_reference||r.reference)}</strong><span>${esc(r.commodity_name_en||r.commodity||'')} · ${esc(r.origin_district||r.origin||'')} → ${esc(r.destination_district||r.destination||'')}</span></div><div><strong>${Number(r.agreed_quantity_kg||r.quantityKg||0).toLocaleString()} kg</strong><span>Tk ${Number(r.agreed_price_bdt_per_kg||r.price||0).toFixed(1)}/kg</span></div><span class="${(r.confirmation_status||r.status)==='confirmed'?'is-confirmed':'is-pending'}">${(r.confirmation_status||r.status)==='confirmed'?t('confirmed'):t('pending')}</span></article>`).join('')}</div>`;
  }

  async function loadRemoteHistory(){
    if(!liveReady())return;
    try{const rows=await api('/rest/v1/rpc/get_my_trade_confirmations',{});renderRecent(rows||[]);}catch(err){console.warn('Trade confirmation history unavailable',err);}
  }

  function localize(){
    document.querySelectorAll('[data-trade-key]').forEach(el=>{el.textContent=t(el.dataset.tradeKey);});
    const mode=document.getElementById('tradeMode');if(mode){mode.textContent=liveReady()?t('live'):t('demo');mode.className='trade-mode '+(liveReady()?'is-live':'is-demo');}
  }

  function attachBuyerMatchButtons(){
    document.querySelectorAll('.buyer-match-row').forEach((row,index)=>{
      if(row.querySelector('.trade-match-button'))return;
      const b=document.createElement('button');b.type='button';b.className='trade-match-button';b.textContent=t('create');
      b.addEventListener('click',()=>{
        const order=window.AgroBuyerWorkflow?.loadLocalOrders?.()[0];const matches=order?window.AgroBuyerWorkflow?.localMatches?.(order):[];const m=matches?.[index];
        if(order&&m)open({source:'demo',commodity:order.commodity,origin:m.origin,destination:order.destination,quantityKg:m.feasibleQuantityKg,price:Math.max(m.sellerFloor,Math.min(order.targetPrice-m.routeCost,m.sellerFloor+2.3)),deliveryDue:order.deliveryFrom,paymentTerms:t('paymentDefault'),qcRequired:true,sellerAccepted:false,buyerAccepted:true});
        else open(demoCandidate());
      });
      row.appendChild(b);
    });
  }

  function init(){
    const css=document.createElement('link');css.rel='stylesheet';css.href='backend/trade-workflow.css';document.head.appendChild(css);
    inject();injectModal();attachBuyerMatchButtons();
    const observer=new MutationObserver(()=>attachBuyerMatchButtons());observer.observe(document.body,{childList:true,subtree:true});
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{localize();renderRecent();attachBuyerMatchButtons();},0));
    window.addEventListener('agro-auth-changed',()=>setTimeout(()=>{localize();loadRemoteHistory();},0));
  }

  window.AgroTrade={open,liveReady,proposeLive,loadRemoteHistory,loadLocal:readLocal};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
