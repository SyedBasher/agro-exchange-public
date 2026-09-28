(function(){
  'use strict';

  const STORAGE_KEY='agro_exchange_sell_offers_v1';
  const DEFAULT_ROUTE_COST={Bogra:3.5,Rangpur:4.2,Joypurhat:3.9};
  const FALLBACK_BUYERS=[
    {name:'Dhaka Fresh Traders',commodity:'Potato',qtyKg:12000,destination:'Dhaka',targetPrice:37.5,delivery:'Tomorrow'},
    {name:'Metro Retail Supply',commodity:'Onion',qtyKg:8000,destination:'Dhaka',targetPrice:55.0,delivery:'2 days'},
    {name:'Gazipur Foods Ltd.',commodity:'Rice',qtyKg:25000,destination:'Gazipur',targetPrice:63.0,delivery:'3 days'}
  ];

  const cfg=window.AGRO_EXCHANGE_CONFIG||{mode:'local'};

  function lang(){
    return document.documentElement.lang==='bn'?'bn':'en';
  }

  function message(en,bn){return lang()==='bn'?bn:en;}

  function id(){
    if(window.crypto&&crypto.randomUUID)return crypto.randomUUID();
    return 'local-'+Date.now()+'-'+Math.random().toString(16).slice(2);
  }

  function normalizeCommodity(value){
    return ({Potato:'POTATO',Onion:'ONION',Rice:'RICE'})[value]||String(value||'').toUpperCase();
  }

  function normalizeGrade(value,commodity){
    if(value==='Grade A')return 'A';
    if(value==='Grade B')return 'B';
    if(value==='Standard')return 'STD';
    return commodity==='RICE'?'STD':null;
  }

  function readOffer(form){
    const fd=new FormData(form);
    const cards=[...form.querySelectorAll('.choice-card')];
    const selected=form.querySelector('.choice-card.selected');
    const commodity=String(fd.get('commodity')||'');
    const commodityCode=normalizeCommodity(commodity);
    return {
      id:id(),
      commodity,
      commodityCode,
      grade:String(fd.get('grade')||''),
      gradeCode:normalizeGrade(String(fd.get('grade')||''),commodityCode),
      quantityKg:Number(fd.get('quantity')),
      origin:String(fd.get('origin')||''),
      minimumPrice:Number(fd.get('price')),
      availableFrom:String(fd.get('date')||''),
      fulfilmentPreference:selected===cards[1]?'farm_pickup':'collection_base',
      status:'open',
      createdAt:new Date().toISOString(),
      persistenceMode:'local'
    };
  }

  function validateOffer(offer){
    if(!offer.commodity||!offer.origin||!offer.availableFrom)throw new Error(message('Please complete commodity, origin and availability date.','পণ্য, উৎপত্তিস্থল ও উপলব্ধ তারিখ পূরণ করুন।'));
    if(!Number.isFinite(offer.quantityKg)||offer.quantityKg<=0)throw new Error(message('Quantity must be greater than zero.','পরিমাণ শূন্যের বেশি হতে হবে।'));
    if(!Number.isFinite(offer.minimumPrice)||offer.minimumPrice<0)throw new Error(message('Minimum price is not valid.','সর্বনিম্ন মূল্য সঠিক নয়।'));
  }

  function loadLocalOffers(){
    try{return JSON.parse(localStorage.getItem(STORAGE_KEY)||'[]');}catch{return [];}
  }

  function saveLocalOffer(offer){
    const items=loadLocalOffers();
    items.unshift(offer);
    localStorage.setItem(STORAGE_KEY,JSON.stringify(items.slice(0,50)));
    return offer;
  }

  function candidatePool(){
    try{
      if(typeof buyers!=='undefined'&&Array.isArray(buyers)){
        return buyers.map(b=>({
          name:b.name,
          commodity:b.commodity,
          qtyKg:parseFloat(b.qty)*1000,
          destination:b.destination,
          targetPrice:parseFloat(String(b.price).replace(/[^0-9.]/g,'')),
          delivery:typeof t==='function'?t(b.delivery):b.delivery
        }));
      }
    }catch(_){/* fall through */}
    return FALLBACK_BUYERS;
  }

  function localMatches(offer){
    const routeCost=DEFAULT_ROUTE_COST[offer.origin]||4.0;
    return candidatePool()
      .filter(b=>b.commodity===offer.commodity)
      .map(b=>{
        const feasibleQty=Math.min(offer.quantityKg,b.qtyKg);
        const deliveredCost=offer.minimumPrice+routeCost;
        const netRoom=b.targetPrice-deliveredCost;
        const quantityFit=feasibleQty/Math.max(offer.quantityKg,b.qtyKg);
        const priceScore=Math.max(0,Math.min(1,(netRoom+2)/8));
        const score=Math.round((0.55*priceScore+0.30*quantityFit+0.15)*100);
        return {
          buyerName:b.name,destination:b.destination,targetPrice:b.targetPrice,
          feasibleQuantityKg:feasibleQty,routeCost,deliveredCost,netRoom,score,
          delivery:b.delivery,source:'local-model'
        };
      })
      .filter(m=>m.netRoom>=-1)
      .sort((a,b)=>b.score-a.score);
  }

  function remoteReady(){
    return cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&currentAccessToken();
  }

  function currentAccessToken(){
    return cfg.accessToken||sessionStorage.getItem('agroExchangeAccessToken')||'';
  }

  async function supabaseFetch(path,options={}){
    const token=currentAccessToken();
    const response=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+path,{
      ...options,
      headers:{
        apikey:cfg.anonKey,
        Authorization:'Bearer '+token,
        'Content-Type':'application/json',
        ...(options.headers||{})
      }
    });
    if(!response.ok){
      const text=await response.text();
      throw new Error('Backend '+response.status+': '+text.slice(0,220));
    }
    if(response.status===204)return null;
    return response.json();
  }

  async function saveRemoteOffer(offer){
    const body={
      p_commodity_code:offer.commodityCode,
      p_grade_code:offer.gradeCode,
      p_origin_district:offer.origin,
      p_quantity_kg:offer.quantityKg,
      p_minimum_price:offer.minimumPrice,
      p_available_from:offer.availableFrom,
      p_fulfilment_preference:offer.fulfilmentPreference
    };
    const remoteId=await supabaseFetch('/rest/v1/rpc/post_sell_offer',{method:'POST',body:JSON.stringify(body)});
    return {...offer,id:String(remoteId).replace(/^"|"$/g,''),persistenceMode:'supabase'};
  }

  async function loadRemoteMatches(offer){
    const body={p_sell_offer_id:offer.id};
    const rows=await supabaseFetch('/rest/v1/rpc/get_sell_offer_matches',{method:'POST',body:JSON.stringify(body)});
    return (rows||[]).map(r=>({
      buyerName:r.buyer_name,
      destination:r.destination_district,
      targetPrice:Number(r.buyer_target_bdt_per_kg),
      feasibleQuantityKg:Number(r.feasible_quantity_kg),
      routeCost:Number(r.estimated_route_cost_bdt_per_kg||DEFAULT_ROUTE_COST[offer.origin]||4),
      deliveredCost:Number(offer.minimumPrice)+(Number(r.estimated_route_cost_bdt_per_kg)||DEFAULT_ROUTE_COST[offer.origin]||4),
      netRoom:Number(r.gross_price_room_bdt_per_kg)-(Number(r.estimated_route_cost_bdt_per_kg)||DEFAULT_ROUTE_COST[offer.origin]||4),
      score:Number(r.match_score||0),
      delivery:r.earliest_feasible_date,
      source:'supabase'
    })).sort((a,b)=>b.score-a.score);
  }

  function escapeHtml(value){
    return String(value??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  }

  function renderPersistentResult(offer,items){
    const list=document.getElementById('matchList');
    if(!list)return;
    const old=document.getElementById('latestPersistentOffer');
    if(old)old.remove();
    const wrapper=document.createElement('div');
    wrapper.id='latestPersistentOffer';
    wrapper.className='persistent-offer-panel';
    const modeLabel=offer.persistenceMode==='supabase'
      ?message('Saved to database','ডেটাবেজে সংরক্ষিত')
      :message('Saved on this device','এই ডিভাইসে সংরক্ষিত');
    const rows=items.length?items.map((m,i)=>`<div class="persistent-match-row">
      <div><strong>${i+1}. ${escapeHtml(m.buyerName)}</strong><span>${escapeHtml(offer.origin)} → ${escapeHtml(m.destination)}</span></div>
      <div><span>${message('Feasible quantity','সম্ভাব্য পরিমাণ')}</span><strong>${(m.feasibleQuantityKg/1000).toFixed(1)} t</strong></div>
      <div><span>${message('Buyer target','ক্রেতার লক্ষ্যদর')}</span><strong>Tk ${m.targetPrice.toFixed(1)}/kg</strong></div>
      <div><span>${message('Est. delivered','আনুমানিক পৌঁছানো খরচ')}</span><strong>Tk ${m.deliveredCost.toFixed(1)}/kg</strong></div>
      <div><span>${message('Net room','নিট ব্যবধান')}</span><strong class="${m.netRoom>=0?'positive-room':'negative-room'}">Tk ${m.netRoom.toFixed(1)}/kg</strong></div>
      <div class="persistent-score"><span>${message('Score','স্কোর')}</span><strong>${Math.round(m.score)}</strong></div>
    </div>`).join(''):`<div class="persistent-empty">${message('No economically feasible buyer is available for this offer yet. The offer remains saved.','এই প্রস্তাবের জন্য এখনো অর্থনৈতিকভাবে গ্রহণযোগ্য ক্রেতা পাওয়া যায়নি। প্রস্তাবটি সংরক্ষিত আছে।')}</div>`;
    wrapper.innerHTML=`<div class="persistent-offer-head"><div><div class="section-kicker">${message('LATEST SUPPLY OFFER','সর্বশেষ সরবরাহ প্রস্তাব')}</div><h2>${escapeHtml(offer.commodity)} · ${escapeHtml(offer.origin)}</h2><p>${(offer.quantityKg/1000).toFixed(2)} t · ${message('minimum','সর্বনিম্ন')} Tk ${offer.minimumPrice.toFixed(1)}/kg · ${escapeHtml(offer.availableFrom)}</p></div><span class="status-pill">✓ ${modeLabel}</span></div>${rows}`;
    list.prepend(wrapper);
    const count=document.querySelector('.side-link[data-view="matches"] .nav-count');
    if(count)count.textContent=String(items.length);
  }

  function setBusy(form,busy){
    const button=form.querySelector('button[type="submit"]');
    if(!button)return;
    if(!button.dataset.originalText)button.dataset.originalText=button.textContent;
    button.disabled=busy;
    button.textContent=busy?message('Saving…','সংরক্ষণ হচ্ছে…'):button.dataset.originalText;
  }

  async function handleSubmit(event){
    event.preventDefault();
    event.stopImmediatePropagation();
    const form=event.currentTarget;
    setBusy(form,true);
    try{
      let offer=readOffer(form);
      validateOffer(offer);
      let found;
      if(remoteReady()){
        offer=await saveRemoteOffer(offer);
        found=await loadRemoteMatches(offer);
      }else{
        offer=saveLocalOffer(offer);
        found=localMatches(offer);
      }
      if(typeof showView==='function')showView('matches');
      renderPersistentResult(offer,found);
      if(typeof toast==='function')toast(message(
        offer.persistenceMode==='supabase'?'Offer saved to the database and matched.':'Offer saved on this device and matched. Connect Supabase to make it multi-user.',
        offer.persistenceMode==='supabase'?'প্রস্তাব ডেটাবেজে সংরক্ষিত হয়েছে এবং ম্যাচ করা হয়েছে।':'প্রস্তাব এই ডিভাইসে সংরক্ষিত হয়েছে এবং ম্যাচ করা হয়েছে। বহু ব্যবহারকারীর জন্য Supabase সংযুক্ত করুন।'
      ));
    }catch(err){
      console.error(err);
      if(typeof toast==='function')toast(err.message||message('Could not save the offer.','প্রস্তাব সংরক্ষণ করা যায়নি।'));
    }finally{
      setBusy(form,false);
    }
  }

  function restoreLatest(){
    if(remoteReady())return;
    const offer=loadLocalOffers()[0];
    if(offer)renderPersistentResult(offer,localMatches(offer));
  }

  function init(){
    const form=document.getElementById('sellForm');
    if(form)form.addEventListener('submit',handleSubmit,true);
    restoreLatest();
  }

  window.AgroPersistence={loadLocalOffers,localMatches,remoteReady};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
