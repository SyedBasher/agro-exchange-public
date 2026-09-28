(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const STORAGE_KEY='agro_exchange_buy_orders_v1';
  const ROUTE_COST={Bogra:3.5,Rangpur:4.2,Joypurhat:3.9};
  const DEMO_SUPPLY=[
    {commodity:'Potato',commodityCode:'POTATO',origin:'Bogra',quantityKg:120000,floor:29.20,gradeCode:'A',verified:true},
    {commodity:'Onion',commodityCode:'ONION',origin:'Bogra',quantityKg:65000,floor:46.50,gradeCode:'A',verified:true},
    {commodity:'Rice',commodityCode:'RICE',origin:'Rangpur',quantityKg:198000,floor:54.80,gradeCode:'STD',verified:true}
  ];

  const copy={
    en:{
      kicker:'BUYER WORKFLOW',title:'Post procurement demand',sub:'State what you need and compare feasible supply before committing.',
      commodity:'Commodity',grade:'Quality / grade',quantity:'Quantity (kg)',destination:'Destination',target:'Target delivered price (Tk/kg)',from:'Delivery from',until:'Delivery until',
      potato:'Potato',onion:'Onion',rice:'Rice',gradeA:'Grade A',standard:'Standard',dhaka:'Dhaka',submit:'Find compatible supply',
      approved:'Approved buyer account',local:'Workflow test · device only',farmer:'Buyer approval required',
      noteApproved:'This demand will be written to the shared Agro-Exchange database.',
      noteLocal:'Until an approved buyer account is signed in, this form remains a safe device-local workflow test.',
      savedDb:'Demand saved to database',savedLocal:'Demand saved on this device',matches:'Compatible supply',noMatches:'No economically feasible supply is available for this demand yet.',
      origin:'Origin',available:'Feasible qty',sellerFloor:'Seller floor',delivered:'Est. delivered',room:'Price room',score:'Score',simulated:'simulated',
      badDates:'Delivery end date cannot be before the start date.',badQty:'Quantity must be greater than zero.',badPrice:'Target price is not valid.'
    },
    bn:{
      kicker:'ক্রেতা ওয়ার্কফ্লো',title:'ক্রয় চাহিদা পোস্ট করুন',sub:'কী প্রয়োজন তা জানান এবং সিদ্ধান্তের আগে সম্ভাব্য সরবরাহ তুলনা করুন।',
      commodity:'পণ্য',grade:'মান / গ্রেড',quantity:'পরিমাণ (কেজি)',destination:'গন্তব্য',target:'লক্ষ্য পৌঁছানো মূল্য (টাকা/কেজি)',from:'ডেলিভারি শুরু',until:'ডেলিভারি শেষ',
      potato:'আলু',onion:'পেঁয়াজ',rice:'চাল',gradeA:'গ্রেড A',standard:'স্ট্যান্ডার্ড',dhaka:'ঢাকা',submit:'সম্ভাব্য সরবরাহ খুঁজুন',
      approved:'অনুমোদিত ক্রেতা অ্যাকাউন্ট',local:'ওয়ার্কফ্লো পরীক্ষা · শুধু ডিভাইসে',farmer:'ক্রেতা অনুমোদন প্রয়োজন',
      noteApproved:'এই চাহিদা Agro-Exchange-এর শেয়ার্ড ডেটাবেজে সংরক্ষিত হবে।',
      noteLocal:'অনুমোদিত ক্রেতা অ্যাকাউন্টে সাইন ইন না করা পর্যন্ত এই ফর্মটি নিরাপদ ডিভাইস-লোকাল ওয়ার্কফ্লো পরীক্ষা হিসেবে থাকবে।',
      savedDb:'চাহিদা ডেটাবেজে সংরক্ষিত',savedLocal:'চাহিদা এই ডিভাইসে সংরক্ষিত',matches:'সম্ভাব্য সরবরাহ',noMatches:'এই চাহিদার জন্য এখনো অর্থনৈতিকভাবে গ্রহণযোগ্য সরবরাহ পাওয়া যায়নি।',
      origin:'উৎপত্তিস্থল',available:'সম্ভাব্য পরিমাণ',sellerFloor:'বিক্রেতার সর্বনিম্ন দর',delivered:'আনুমানিক পৌঁছানো',room:'মূল্য ব্যবধান',score:'স্কোর',simulated:'সিমুলেটেড',
      badDates:'ডেলিভারি শেষের তারিখ শুরুর তারিখের আগে হতে পারে না।',badQty:'পরিমাণ শূন্যের বেশি হতে হবে।',badPrice:'লক্ষ্য মূল্য সঠিক নয়।'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(key){return copy[lang()][key]||key;}
  function esc(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function remoteReady(){return cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token()&&profile()?.role==='buyer';}

  function isoDate(offset){const d=new Date();d.setHours(12,0,0,0);d.setDate(d.getDate()+offset);return d.toISOString().slice(0,10);}
  function uid(){return window.crypto?.randomUUID?.()||('local-'+Date.now()+'-'+Math.random().toString(16).slice(2));}
  function commodityCode(v){return ({Potato:'POTATO',Onion:'ONION',Rice:'RICE'})[v]||String(v||'').toUpperCase();}
  function gradeCode(commodity){return commodity==='Rice'?'STD':'A';}

  function readLocal(){try{return JSON.parse(localStorage.getItem(STORAGE_KEY)||'[]');}catch{return [];}}
  function saveLocal(order){const rows=readLocal();rows.unshift(order);localStorage.setItem(STORAGE_KEY,JSON.stringify(rows.slice(0,50)));return order;}

  async function api(path,body){
    const response=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+path,{
      method:'POST',
      headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},
      body:JSON.stringify(body)
    });
    const text=await response.text();
    let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!response.ok)throw new Error(data?.message||data?.error||data||('Backend '+response.status));
    return data;
  }

  async function saveRemote(order){
    const id=await api('/rest/v1/rpc/post_buy_order',{
      p_commodity_code:order.commodityCode,p_grade_code:order.gradeCode,p_destination_district:order.destination,
      p_quantity_kg:order.quantityKg,p_target_price:order.targetPrice,p_delivery_from:order.deliveryFrom,p_delivery_until:order.deliveryUntil
    });
    return {...order,id:String(id).replace(/^"|"$/g,''),persistenceMode:'supabase'};
  }

  async function loadRemoteMatches(order){
    const rows=await api('/rest/v1/rpc/get_buy_order_matches',{p_buy_order_id:order.id});
    return (rows||[]).map(r=>{
      const route=Number(r.estimated_route_cost_bdt_per_kg||4);
      const floor=Number(r.seller_floor_bdt_per_kg);
      return {origin:r.origin_district,feasibleQuantityKg:Number(r.feasible_quantity_kg),sellerFloor:floor,routeCost:route,deliveredCost:floor+route,priceRoom:Number(r.gross_price_room_bdt_per_kg)-route,score:Number(r.match_score||0),verified:Boolean(r.seller_verified),source:'supabase'};
    });
  }

  function localMatches(order){
    return DEMO_SUPPLY.filter(s=>s.commodityCode===order.commodityCode).map(s=>{
      const route=ROUTE_COST[s.origin]||4;
      const delivered=s.floor+route;
      const room=order.targetPrice-delivered;
      const feasible=Math.min(order.quantityKg,s.quantityKg);
      const qtyFit=feasible/Math.max(order.quantityKg,s.quantityKg);
      const priceScore=Math.max(0,Math.min(1,(room+2)/8));
      const score=Math.round((0.55*priceScore+0.30*qtyFit+0.15)*100);
      return {origin:s.origin,feasibleQuantityKg:feasible,sellerFloor:s.floor,routeCost:route,deliveredCost:delivered,priceRoom:room,score,verified:s.verified,source:'local-model'};
    }).filter(m=>m.priceRoom>=-1).sort((a,b)=>b.score-a.score);
  }

  function statusState(){
    const p=profile();
    if(remoteReady())return {label:t('approved'),note:t('noteApproved'),cls:'is-live'};
    if(token()&&p?.role!=='buyer')return {label:t('farmer'),note:t('noteLocal'),cls:'is-waiting'};
    return {label:t('local'),note:t('noteLocal'),cls:'is-local'};
  }

  function inject(){
    if(document.getElementById('buyerWorkflow'))return;
    const demand=document.getElementById('demand');
    if(!demand)return;
    const card=document.createElement('section');
    card.id='buyerWorkflow';
    card.className='card buyer-workflow-card';
    card.innerHTML=`
      <div class="buyer-workflow-head">
        <div><div class="section-kicker" data-buyer-key="kicker"></div><h2 data-buyer-key="title"></h2><p data-buyer-key="sub"></p></div>
        <span id="buyerWorkflowStatus" class="buyer-workflow-status"></span>
      </div>
      <form id="buyerDemandForm" class="buyer-demand-form">
        <label><span data-buyer-key="commodity"></span><select name="commodity" id="buyerCommodity"><option value="Potato" data-buyer-key="potato"></option><option value="Onion" data-buyer-key="onion"></option><option value="Rice" data-buyer-key="rice"></option></select></label>
        <label><span data-buyer-key="grade"></span><select name="grade" id="buyerGrade"><option value="A" data-buyer-key="gradeA"></option></select></label>
        <label><span data-buyer-key="quantity"></span><input name="quantity" type="number" inputmode="decimal" min="1" step="1" value="12000" required></label>
        <label><span data-buyer-key="destination"></span><select name="destination"><option value="Dhaka" data-buyer-key="dhaka"></option></select></label>
        <label><span data-buyer-key="target"></span><input name="price" type="number" inputmode="decimal" min="0" step="0.1" value="37.5" required></label>
        <label><span data-buyer-key="from"></span><input name="deliveryFrom" type="date" value="${isoDate(1)}" required></label>
        <label><span data-buyer-key="until"></span><input name="deliveryUntil" type="date" value="${isoDate(3)}"></label>
        <div class="buyer-submit-row"><button class="button primary" type="submit" data-buyer-key="submit"></button><small id="buyerWorkflowNote"></small></div>
      </form>
      <div id="buyerWorkflowResults" class="buyer-workflow-results"></div>`;
    const heading=demand.querySelector('.page-heading');
    if(heading)heading.insertAdjacentElement('afterend',card);else demand.prepend(card);
    document.getElementById('buyerDemandForm').addEventListener('submit',submit);
    document.getElementById('buyerCommodity').addEventListener('change',updateGrade);
    localize();updateGrade();restore();
  }

  function updateGrade(){
    const commodity=document.getElementById('buyerCommodity')?.value;
    const select=document.getElementById('buyerGrade');
    if(!select)return;
    select.innerHTML=commodity==='Rice'?`<option value="STD">${t('standard')}</option>`:`<option value="A">${t('gradeA')}</option>`;
  }

  function localize(){
    document.querySelectorAll('#buyerWorkflow [data-buyer-key]').forEach(el=>{el.textContent=t(el.dataset.buyerKey);});
    const state=statusState();
    const badge=document.getElementById('buyerWorkflowStatus');
    if(badge){badge.textContent=state.label;badge.className='buyer-workflow-status '+state.cls;}
    const note=document.getElementById('buyerWorkflowNote');if(note)note.textContent=state.note;
  }

  function readOrder(form){
    const fd=new FormData(form);const commodity=String(fd.get('commodity')||'');
    return {id:uid(),commodity,commodityCode:commodityCode(commodity),gradeCode:gradeCode(commodity),quantityKg:Number(fd.get('quantity')),destination:String(fd.get('destination')||'Dhaka'),targetPrice:Number(fd.get('price')),deliveryFrom:String(fd.get('deliveryFrom')||''),deliveryUntil:String(fd.get('deliveryUntil')||''),createdAt:new Date().toISOString(),persistenceMode:'local'};
  }

  function validate(order){
    if(!Number.isFinite(order.quantityKg)||order.quantityKg<=0)throw new Error(t('badQty'));
    if(!Number.isFinite(order.targetPrice)||order.targetPrice<0)throw new Error(t('badPrice'));
    if(order.deliveryUntil&&order.deliveryUntil<order.deliveryFrom)throw new Error(t('badDates'));
  }

  function render(order,matches){
    const target=document.getElementById('buyerWorkflowResults');if(!target)return;
    const saved=order.persistenceMode==='supabase'?t('savedDb'):t('savedLocal');
    const rows=matches.length?matches.map((m,i)=>`<div class="buyer-match-row">
      <div class="buyer-match-main"><strong>${i+1}. ${esc(m.origin)} → ${esc(order.destination)}</strong><span>${m.verified?'✓ ':''}${m.source==='local-model'?t('simulated'):''}</span></div>
      <div><span>${t('available')}</span><strong>${(m.feasibleQuantityKg/1000).toFixed(1)} t</strong></div>
      <div><span>${t('sellerFloor')}</span><strong>Tk ${m.sellerFloor.toFixed(1)}/kg</strong></div>
      <div><span>${t('delivered')}</span><strong>Tk ${m.deliveredCost.toFixed(1)}/kg</strong></div>
      <div><span>${t('room')}</span><strong class="${m.priceRoom>=0?'positive-room':'negative-room'}">Tk ${m.priceRoom.toFixed(1)}/kg</strong></div>
      <div class="buyer-score"><span>${t('score')}</span><strong>${Math.round(m.score)}</strong></div>
    </div>`).join(''):`<div class="buyer-no-match">${t('noMatches')}</div>`;
    target.innerHTML=`<div class="buyer-result-head"><strong>✓ ${saved}</strong><span>${esc(order.commodity)} · ${(order.quantityKg/1000).toFixed(2)} t · Tk ${order.targetPrice.toFixed(1)}/kg</span></div><h3>${t('matches')}</h3>${rows}`;
  }

  function setBusy(form,busy){const b=form.querySelector('button[type="submit"]');if(!b)return;b.disabled=busy;b.dataset.label=b.dataset.label||b.textContent;b.textContent=busy?'…':(busy?b.textContent:t('submit'));}

  async function submit(e){
    e.preventDefault();const form=e.currentTarget;setBusy(form,true);
    try{
      let order=readOrder(form);validate(order);let matches;
      if(remoteReady()){order=await saveRemote(order);matches=await loadRemoteMatches(order);}
      else{order=saveLocal(order);matches=localMatches(order);}
      render(order,matches);
      if(typeof toast==='function')toast(order.persistenceMode==='supabase'?t('savedDb'):t('savedLocal'));
    }catch(err){console.error(err);if(typeof toast==='function')toast(err.message||'Could not save demand.');}
    finally{setBusy(form,false);localize();}
  }

  function restore(){const latest=readLocal()[0];if(latest)render(latest,localMatches(latest));}

  function init(){
    const css=document.createElement('link');css.rel='stylesheet';css.href='backend/buyer-workflow.css';document.head.appendChild(css);
    inject();
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{localize();updateGrade();const latest=readLocal()[0];if(latest)render(latest,localMatches(latest));},0));
    window.addEventListener('agro-auth-changed',()=>setTimeout(localize,0));
  }

  window.AgroBuyerWorkflow={remoteReady,localMatches,loadLocalOrders:readLocal};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
