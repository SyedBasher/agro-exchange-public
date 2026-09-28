(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const TRADE_KEY='agro_exchange_trade_confirmations_v1';
  const SETTLEMENT_KEY='agro_exchange_settlements_v1';
  let rows=[];
  let active=null;

  const copy={
    en:{
      kicker:'TRADES & SETTLEMENT',title:'Delivery receipt & payment status',sub:'Confirm buyer receipt, record payment references and close a trade only after payment is acknowledged.',
      live:'Live shared workflow',local:'Workflow test · device only',notice:'Agro-Exchange records status and references only. It does not hold, escrow or transfer money in this version.',
      refresh:'Refresh',empty:'No delivered or settled trades are available.',trade:'Trade',route:'Route',commodity:'Commodity',amount:'Contract amount',receipt:'Buyer receipt',payment:'Payment',action:'Action',
      delivered:'Delivered',settled:'Settled',disputed:'Disputed',awaitReceipt:'Awaiting buyer receipt',accepted:'Receipt accepted',due:'Payment due',initiated:'Payment initiated',partial:'Partially paid',paid:'Paid',failed:'Payment failed',
      confirmReceipt:'Confirm receipt',reportIssue:'Report discrepancy',recordPayment:'Record payment',confirmPayment:'Confirm funds received',markFailed:'Mark payment failed',view:'View',
      receivedQty:'Quantity received (kg)',receiptNotes:'Receipt notes',discrepancy:'Discrepancy reason',acceptDelivery:'Accept delivery',submitReceipt:'Save receipt decision',
      method:'Payment method',bank:'Bank transfer',mfs:'Mobile financial service',cash:'Cash',other:'Other',reference:'Payment reference',paymentAmount:'Payment amount (Tk)',paymentNotes:'Payment notes',submitPayment:'Record payment initiated',
      sellerConfirm:'Seller confirmation',sellerConfirmHelp:'Confirm only after the funds have actually been received through the stated method.',confirmNotes:'Confirmation notes',confirmNow:'Confirm payment received',
      contractBasis:'Payment basis',contractBasisHelp:'Default amount due is agreed quantity × agreed produce price. QC-measured weight does not automatically change the commercial amount.',
      savedReceipt:'Buyer receipt saved',savedPayment:'Payment initiation recorded',savedConfirm:'Payment confirmed',savedFailed:'Payment marked failed',reason:'Reason',close:'Close',
      referenceRequired:'A payment reference is required for non-cash payments.',amountInvalid:'Enter a valid payment amount.',reasonRequired:'Enter a discrepancy or failure reason.',simulated:'SIMULATED',buyerOnly:'Buyer organization confirmation required.',sellerOnly:'Seller confirmation required.'
    },
    bn:{
      kicker:'লেনদেন ও নিষ্পত্তি',title:'ডেলিভারি গ্রহণ ও পেমেন্ট অবস্থা',sub:'ক্রেতার গ্রহণ নিশ্চিত করুন, পেমেন্ট রেফারেন্স নথিবদ্ধ করুন এবং অর্থপ্রাপ্তি নিশ্চিত হওয়ার পর লেনদেন বন্ধ করুন।',
      live:'লাইভ শেয়ার্ড ওয়ার্কফ্লো',local:'ওয়ার্কফ্লো পরীক্ষা · শুধু ডিভাইসে',notice:'এই সংস্করণে Agro-Exchange শুধু অবস্থা ও রেফারেন্স নথিবদ্ধ করে। প্ল্যাটফর্ম অর্থ ধারণ, এসক্রো বা স্থানান্তর করে না।',
      refresh:'রিফ্রেশ',empty:'কোনো ডেলিভারি বা নিষ্পত্তি লেনদেন পাওয়া যায়নি।',trade:'লেনদেন',route:'রুট',commodity:'পণ্য',amount:'চুক্তির পরিমাণ',receipt:'ক্রেতার গ্রহণ',payment:'পেমেন্ট',action:'করণীয়',
      delivered:'ডেলিভারি হয়েছে',settled:'নিষ্পত্তি হয়েছে',disputed:'বিরোধাধীন',awaitReceipt:'ক্রেতার গ্রহণের অপেক্ষায়',accepted:'গ্রহণ নিশ্চিত',due:'পেমেন্ট বাকি',initiated:'পেমেন্ট শুরু হয়েছে',partial:'আংশিক পরিশোধ',paid:'পরিশোধিত',failed:'পেমেন্ট ব্যর্থ',
      confirmReceipt:'গ্রহণ নিশ্চিত করুন',reportIssue:'অমিল জানান',recordPayment:'পেমেন্ট নথিবদ্ধ করুন',confirmPayment:'অর্থপ্রাপ্তি নিশ্চিত করুন',markFailed:'পেমেন্ট ব্যর্থ',view:'দেখুন',
      receivedQty:'প্রাপ্ত পরিমাণ (কেজি)',receiptNotes:'গ্রহণ নোট',discrepancy:'অমিলের কারণ',acceptDelivery:'ডেলিভারি গ্রহণ',submitReceipt:'গ্রহণ সিদ্ধান্ত সংরক্ষণ',
      method:'পেমেন্ট পদ্ধতি',bank:'ব্যাংক ট্রান্সফার',mfs:'মোবাইল ফাইন্যান্সিয়াল সার্ভিস',cash:'নগদ',other:'অন্যান্য',reference:'পেমেন্ট রেফারেন্স',paymentAmount:'পেমেন্ট পরিমাণ (টাকা)',paymentNotes:'পেমেন্ট নোট',submitPayment:'পেমেন্ট শুরু নথিবদ্ধ করুন',
      sellerConfirm:'বিক্রেতার নিশ্চিতকরণ',sellerConfirmHelp:'উল্লিখিত মাধ্যমে অর্থ সত্যিই পাওয়ার পরেই নিশ্চিত করুন।',confirmNotes:'নিশ্চিতকরণ নোট',confirmNow:'অর্থপ্রাপ্তি নিশ্চিত করুন',
      contractBasis:'পেমেন্টের ভিত্তি',contractBasisHelp:'ডিফল্ট পাওনা = সম্মত পরিমাণ × সম্মত পণ্যমূল্য। QC-তে মাপা ওজন স্বয়ংক্রিয়ভাবে বাণিজ্যিক অঙ্ক পরিবর্তন করে না।',
      savedReceipt:'ক্রেতার গ্রহণ সংরক্ষিত হয়েছে',savedPayment:'পেমেন্ট শুরু নথিবদ্ধ হয়েছে',savedConfirm:'পেমেন্ট নিশ্চিত হয়েছে',savedFailed:'পেমেন্ট ব্যর্থ হিসেবে নথিবদ্ধ হয়েছে',reason:'কারণ',close:'বন্ধ করুন',
      referenceRequired:'নগদ ছাড়া অন্য পেমেন্টে রেফারেন্স প্রয়োজন।',amountInvalid:'সঠিক পেমেন্ট পরিমাণ দিন।',reasonRequired:'অমিল বা ব্যর্থতার কারণ লিখুন।',simulated:'সিমুলেটেড',buyerOnly:'ক্রেতা প্রতিষ্ঠানের নিশ্চিতকরণ প্রয়োজন।',sellerOnly:'বিক্রেতার নিশ্চিতকরণ প্রয়োজন।'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token());}
  function role(){return profile()?.role||'';}
  function read(key){try{return JSON.parse(localStorage.getItem(key)||'[]');}catch{return [];}}
  function write(key,data){localStorage.setItem(key,JSON.stringify(data.slice(0,100)));}
  function money(v){return 'Tk '+Number(v||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{minimumFractionDigits:0,maximumFractionDigits:2});}
  function kg(v){return Number(v||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:1})+' kg';}
  function uid(){return window.crypto?.randomUUID?.()||('local-'+Date.now()+'-'+Math.random().toString(16).slice(2));}

  async function rpc(name,body={}){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body)});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  function localRows(){
    const state=read(SETTLEMENT_KEY);const byTrade=new Map(state.map(x=>[x.tradeId,x]));
    const trades=read(TRADE_KEY).filter(x=>['delivered','settled','disputed'].includes(x.tradeStatus));
    const out=trades.map(x=>{
      const saved=byTrade.get(x.tradeId)||{};const qty=Number(x.quantityKg||0),price=Number(x.price||0);const due=Number(saved.amountDue??(qty*price));
      return {trade_id:x.tradeId,confirmation_reference:x.reference,trade_status:saved.tradeStatus||x.tradeStatus,commodity_name_en:x.commodity||'Potato',commodity_name_bn:x.commodity==='Rice'?'চাল':x.commodity==='Onion'?'পেঁয়াজ':'আলু',origin_district:x.origin||'Bogra',destination_district:x.destination||'Dhaka',agreed_quantity_kg:qty,agreed_price_bdt_per_kg:price,receipt_status:saved.receiptStatus||null,received_quantity_kg:saved.receivedQuantityKg??null,amount_due_bdt:due,obligation_status:saved.obligationStatus||null,total_confirmed_bdt:Number(saved.totalConfirmed||0),remaining_due_bdt:Math.max(due-Number(saved.totalConfirmed||0),0),latest_payment_id:saved.latestPaymentId||null,latest_payment_status:saved.latestPaymentStatus||null,latest_payment_method:saved.latestPaymentMethod||null,latest_payment_reference:saved.latestPaymentReference||null,is_seller:true,is_buyer:true,source:'local'};
    });
    if(!out.length){out.push({trade_id:'TR-DEMO-SET-001',confirmation_reference:'AX-DEMO-SET-001',trade_status:'delivered',commodity_name_en:'Potato',commodity_name_bn:'আলু',origin_district:'Bogra',destination_district:'Dhaka',agreed_quantity_kg:5000,agreed_price_bdt_per_kg:31.5,receipt_status:null,received_quantity_kg:null,amount_due_bdt:157500,obligation_status:null,total_confirmed_bdt:0,remaining_due_bdt:157500,latest_payment_id:null,latest_payment_status:null,latest_payment_method:null,latest_payment_reference:null,is_seller:true,is_buyer:true,source:'demo'});}
    return out;
  }

  function injectView(){
    if(document.getElementById('settlement'))return;
    const main=document.querySelector('main.content');if(!main)return;
    const s=document.createElement('section');s.id='settlement';s.className='view';
    s.innerHTML=`<div class="page-heading"><div><div class="breadcrumb" data-set-key="kicker"></div><h1 data-set-key="title"></h1><p data-set-key="sub"></p></div><div class="heading-actions"><button id="setRefresh" class="button secondary" type="button" data-set-key="refresh"></button></div></div><div class="set-notice"><strong id="setMode"></strong><span data-set-key="notice"></span></div><section class="card set-card"><div id="settlementList" class="set-list"></div></section>`;
    main.appendChild(s);document.getElementById('setRefresh').addEventListener('click',refresh);wireNav();localize();refresh();
  }

  function wireNav(){
    const old=document.querySelector('[data-i18n="nav_trades"]')?.closest('.side-link');if(!old)return;
    const btn=old.cloneNode(true);btn.removeAttribute('data-action');btn.dataset.view='settlement';old.replaceWith(btn);btn.addEventListener('click',showView);
  }
  function showView(){document.querySelectorAll('.view').forEach(v=>v.classList.remove('active-view'));document.getElementById('settlement')?.classList.add('active-view');document.querySelectorAll('.side-link[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view==='settlement'));document.querySelector('.sidebar')?.classList.remove('open');document.getElementById('mobileOverlay')?.classList.remove('show');window.scrollTo({top:0,behavior:'smooth'});refresh();}
  function localize(){document.querySelectorAll('#settlement [data-set-key],#setModal [data-set-key]').forEach(el=>el.textContent=t(el.dataset.setKey));const mode=document.getElementById('setMode');if(mode)mode.textContent=liveReady()?t('live'):t('local');}

  async function refresh(){
    try{rows=liveReady()?await rpc('get_my_settlements'):localRows();render();}catch(err){const el=document.getElementById('settlementList');if(el)el.innerHTML=`<div class="set-empty">${esc(err.message)}</div>`;}
  }

  function receiptLabel(r){if(r.trade_status==='disputed'||r.receipt_status==='disputed')return t('disputed');if(r.receipt_status==='accepted')return t('accepted');return t('awaitReceipt');}
  function paymentLabel(r){if(r.trade_status==='settled'||r.obligation_status==='paid')return t('paid');if(r.latest_payment_status==='failed')return t('failed');if(r.obligation_status==='partially_paid')return t('partial');if(r.latest_payment_status==='initiated'||r.obligation_status==='initiated')return t('initiated');if(r.obligation_status==='due')return t('due');return '—';}
  function canBuyer(r){return !liveReady()||role()==='admin'||r.is_buyer;}
  function canSeller(r){return !liveReady()||role()==='admin'||r.is_seller;}
  function actions(r,i){
    if(r.trade_status==='settled'||r.trade_status==='disputed')return `<button class="button secondary set-action" data-act="view" data-i="${i}">${t('view')}</button>`;
    if(!r.receipt_status&&canBuyer(r))return `<button class="button primary set-action" data-act="receipt" data-i="${i}">${t('confirmReceipt')}</button>`;
    if(r.receipt_status==='accepted'&&['due','partially_paid'].includes(r.obligation_status||'due')&&canBuyer(r))return `<button class="button primary set-action" data-act="pay" data-i="${i}">${t('recordPayment')}</button>`;
    if(r.latest_payment_status==='initiated'&&canSeller(r))return `<button class="button primary set-action" data-act="confirm" data-i="${i}">${t('confirmPayment')}</button>`;
    return `<button class="button secondary set-action" data-act="view" data-i="${i}">${t('view')}</button>`;
  }
  function render(){
    const target=document.getElementById('settlementList');if(!target)return;if(!rows?.length){target.innerHTML=`<div class="set-empty">${t('empty')}</div>`;return;}
    target.innerHTML=rows.map((r,i)=>`<article class="set-row"><div class="set-main"><span class="set-ref">${esc(r.confirmation_reference||r.trade_id)}</span><strong>${esc(lang()==='bn'?(r.commodity_name_bn||r.commodity_name_en):(r.commodity_name_en||r.commodity_code||''))}</strong><span>${esc(r.origin_district)} → ${esc(r.destination_district)}</span></div><div><span>${t('amount')}</span><strong>${money(r.amount_due_bdt||Number(r.agreed_quantity_kg)*Number(r.agreed_price_bdt_per_kg))}</strong></div><div><span>${t('receipt')}</span><strong>${receiptLabel(r)}</strong></div><div><span>${t('payment')}</span><strong>${paymentLabel(r)}</strong></div><div class="set-row-action">${actions(r,i)}</div></article>`).join('');
    target.querySelectorAll('.set-action').forEach(b=>b.addEventListener('click',()=>openAction(rows[Number(b.dataset.i)],b.dataset.act)));
  }

  function injectModal(){
    if(document.getElementById('setModal'))return;
    const m=document.createElement('div');m.id='setModal';m.className='set-modal';m.innerHTML=`<div class="set-backdrop" data-set-close></div><section class="set-sheet"><button class="set-close" data-set-close type="button">×</button><div class="set-brand">Agro-Exchange</div><div id="setModalBody"></div></section>`;document.body.appendChild(m);m.querySelectorAll('[data-set-close]').forEach(x=>x.addEventListener('click',closeModal));
  }
  function closeModal(){document.getElementById('setModal')?.classList.remove('open');}
  function summary(r){return `<div class="set-summary"><div><span>${t('trade')}</span><strong>${esc(r.confirmation_reference||r.trade_id)}</strong></div><div><span>${t('route')}</span><strong>${esc(r.origin_district)} → ${esc(r.destination_district)}</strong></div><div><span>${t('amount')}</span><strong>${money(r.amount_due_bdt||Number(r.agreed_quantity_kg)*Number(r.agreed_price_bdt_per_kg))}</strong></div></div><div class="set-basis"><strong>${t('contractBasis')}</strong><span>${t('contractBasisHelp')}</span></div>`;}

  function openAction(r,act){injectModal();active=r;const body=document.getElementById('setModalBody');
    if(act==='receipt')body.innerHTML=`<div class="section-kicker">${t('receipt')}</div><h2>${t('confirmReceipt')}</h2>${summary(r)}<form id="receiptForm" class="set-form"><label><span>${t('receivedQty')}</span><input name="qty" type="number" min="0.1" step="0.1" inputmode="decimal" value="${Number(r.agreed_quantity_kg||0)}"></label><label><span>${t('acceptDelivery')}</span><select name="decision"><option value="accept">${t('accepted')}</option><option value="dispute">${t('reportIssue')}</option></select></label><label class="set-wide"><span>${t('receiptNotes')}</span><textarea name="notes"></textarea></label><label class="set-wide"><span>${t('discrepancy')}</span><textarea name="reason"></textarea></label><button class="button primary set-wide" type="submit">${t('submitReceipt')}</button></form>`;
    else if(act==='pay')body.innerHTML=`<div class="section-kicker">${t('payment')}</div><h2>${t('recordPayment')}</h2>${summary(r)}<form id="payForm" class="set-form"><label><span>${t('method')}</span><select name="method"><option value="bank_transfer">${t('bank')}</option><option value="mobile_financial_service">${t('mfs')}</option><option value="cash">${t('cash')}</option><option value="other">${t('other')}</option></select></label><label><span>${t('paymentAmount')}</span><input name="amount" type="number" min="0.01" step="0.01" inputmode="decimal" value="${Number(r.remaining_due_bdt||r.amount_due_bdt||0).toFixed(2)}"></label><label class="set-wide"><span>${t('reference')}</span><input name="reference" type="text" maxlength="120"></label><label class="set-wide"><span>${t('paymentNotes')}</span><textarea name="notes"></textarea></label><button class="button primary set-wide" type="submit">${t('submitPayment')}</button></form>`;
    else if(act==='confirm')body.innerHTML=`<div class="section-kicker">${t('sellerConfirm')}</div><h2>${t('confirmPayment')}</h2>${summary(r)}<p class="set-help">${t('sellerConfirmHelp')}</p><form id="confirmForm" class="set-form"><label class="set-wide"><span>${t('confirmNotes')}</span><textarea name="notes"></textarea></label><button class="button primary set-wide" type="submit">${t('confirmNow')}</button></form><button id="failedPayment" class="button secondary set-danger" type="button">${t('markFailed')}</button>`;
    else body.innerHTML=`<div class="section-kicker">${t('trade')}</div><h2>${esc(r.confirmation_reference||r.trade_id)}</h2>${summary(r)}<div class="set-detail"><p><strong>${t('receipt')}:</strong> ${receiptLabel(r)}</p><p><strong>${t('payment')}:</strong> ${paymentLabel(r)}</p><p><strong>${t('receivedQty')}:</strong> ${r.received_quantity_kg?kg(r.received_quantity_kg):'—'}</p><p><strong>${t('reference')}:</strong> ${esc(r.latest_payment_reference||'—')}</p></div>`;
    document.getElementById('setModal').classList.add('open');document.getElementById('receiptForm')?.addEventListener('submit',submitReceipt);document.getElementById('payForm')?.addEventListener('submit',submitPayment);document.getElementById('confirmForm')?.addEventListener('submit',submitConfirm);document.getElementById('failedPayment')?.addEventListener('click',markFailed);
  }

  function localState(tradeId){const all=read(SETTLEMENT_KEY);let s=all.find(x=>x.tradeId===tradeId);if(!s){s={tradeId};all.unshift(s);}return {all,s};}
  function saveLocal(all){write(SETTLEMENT_KEY,all);}
  function updateLocalTrade(tradeId,status){const a=read(TRADE_KEY),x=a.find(y=>y.tradeId===tradeId);if(x){x.tradeStatus=status;write(TRADE_KEY,a);}}

  async function submitReceipt(e){e.preventDefault();const f=e.currentTarget,accepted=f.elements.decision.value==='accept',reason=String(f.elements.reason.value||'').trim(),qty=Number(f.elements.qty.value||0);if(!accepted&&!reason){toast?.(t('reasonRequired'));return;}try{
    if(liveReady()){if(!canBuyer(active))throw new Error(t('buyerOnly'));await rpc('confirm_delivery_receipt',{p_trade_id:active.trade_id,p_received_quantity_kg:qty||null,p_accepted:accepted,p_notes:String(f.elements.notes.value||'')||null,p_discrepancy_reason:reason||null});}
    else{const {all,s}=localState(active.trade_id);s.receiptStatus=accepted?'accepted':'disputed';s.receivedQuantityKg=qty||null;s.amountDue=Number(active.agreed_quantity_kg)*Number(active.agreed_price_bdt_per_kg);s.obligationStatus=accepted?'due':'disputed';s.tradeStatus=accepted?'delivered':'disputed';saveLocal(all);updateLocalTrade(active.trade_id,s.tradeStatus);}
    closeModal();toast?.(t('savedReceipt'));await refresh();
  }catch(err){toast?.(err.message||'Could not save receipt.');}}

  async function submitPayment(e){e.preventDefault();const f=e.currentTarget,method=f.elements.method.value,ref=String(f.elements.reference.value||'').trim(),amount=Number(f.elements.amount.value||0);if(!Number.isFinite(amount)||amount<=0){toast?.(t('amountInvalid'));return;}if(method!=='cash'&&!ref){toast?.(t('referenceRequired'));return;}try{
    if(liveReady()){if(!canBuyer(active))throw new Error(t('buyerOnly'));await rpc('initiate_trade_payment',{p_trade_id:active.trade_id,p_method:method,p_external_reference:ref||null,p_amount_bdt:amount,p_notes:String(f.elements.notes.value||'')||null});}
    else{const {all,s}=localState(active.trade_id);s.latestPaymentId=uid();s.latestPaymentStatus='initiated';s.latestPaymentMethod=method;s.latestPaymentReference=ref;s.latestPaymentAmount=amount;s.obligationStatus='initiated';s.amountDue=Number(active.amount_due_bdt||Number(active.agreed_quantity_kg)*Number(active.agreed_price_bdt_per_kg));s.totalConfirmed=Number(s.totalConfirmed||0);s.tradeStatus='delivered';saveLocal(all);}
    closeModal();toast?.(t('savedPayment'));await refresh();
  }catch(err){toast?.(err.message||'Could not record payment.');}}

  async function submitConfirm(e){e.preventDefault();const f=e.currentTarget;try{
    if(liveReady()){if(!canSeller(active))throw new Error(t('sellerOnly'));await rpc('confirm_trade_payment',{p_payment_id:active.latest_payment_id,p_notes:String(f.elements.notes.value||'')||null});}
    else{const {all,s}=localState(active.trade_id);const amt=Number(s.latestPaymentAmount||active.remaining_due_bdt||active.amount_due_bdt||0);s.totalConfirmed=Number(s.totalConfirmed||0)+amt;s.latestPaymentStatus='confirmed';s.amountDue=Number(s.amountDue||active.amount_due_bdt||0);if(s.totalConfirmed+0.01>=s.amountDue){s.obligationStatus='paid';s.tradeStatus='settled';updateLocalTrade(active.trade_id,'settled');}else{s.obligationStatus='partially_paid';s.tradeStatus='delivered';}saveLocal(all);}
    closeModal();toast?.(t('savedConfirm'));await refresh();
  }catch(err){toast?.(err.message||'Could not confirm payment.');}}

  async function markFailed(){const reason=window.prompt(t('reason'))||'';if(!reason.trim()){toast?.(t('reasonRequired'));return;}try{
    if(liveReady())await rpc('mark_trade_payment_failed',{p_payment_id:active.latest_payment_id,p_reason:reason.trim()});
    else{const {all,s}=localState(active.trade_id);s.latestPaymentStatus='failed';s.obligationStatus=Number(s.totalConfirmed||0)>0?'partially_paid':'due';saveLocal(all);}
    closeModal();toast?.(t('savedFailed'));await refresh();
  }catch(err){toast?.(err.message||'Could not update payment.');}}

  function init(){const css=document.createElement('link');css.rel='stylesheet';css.href='backend/settlement-workflow.css';document.head.appendChild(css);injectView();document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{localize();refresh();},0));window.addEventListener('agro-auth-changed',()=>setTimeout(refresh,0));}
  window.AgroSettlement={refresh,show:showView};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
