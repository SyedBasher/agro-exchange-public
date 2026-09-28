(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const SHIPMENT_KEY='agro_exchange_shipments_v1';
  const TRADE_KEY='agro_exchange_trade_confirmations_v1';
  let readyRows=[];
  let shipmentRows=[];
  let transporters=[];
  let activeTrade=null;
  let activeShipment=null;
  let deliveryFiles=[];

  const copy={
    en:{
      kicker:'LOGISTICS',title:'Dispatch & delivery',sub:'Assign transport, confirm pickup and preserve a traceable delivery record.',
      live:'Live shared workflow',local:'Workflow test · device only',restricted:'Operational role required',
      queue:'Ready for dispatch',queueSub:'Trades cleared by QC and waiting for a transporter.',shipments:'Shipments',shipmentsSub:'Assignments, dispatch status and delivery confirmation.',
      emptyQueue:'No trades are waiting for transport assignment.',emptyShipments:'No shipments are available yet.',
      route:'Route',commodity:'Commodity',dispatchQty:'Dispatch quantity',due:'Delivery due',assign:'Assign transport',
      transporter:'Transporter',vehicle:'Vehicle reference',cost:'Transport cost (Tk)',pickup:'Pickup due',notes:'Assignment notes',createAssignment:'Create assignment',
      assigned:'Assigned',accepted:'Accepted',inTransit:'In transit',delivered:'Delivered',cancelled:'Cancelled',
      acceptJob:'Accept job',dispatch:'Mark dispatched',deliver:'Confirm delivery',viewOnly:'Status only',
      recipient:'Recipient name',deliveryNotes:'Delivery notes',evidence:'Proof of delivery',evidenceHelp:'Up to 4 JPEG/PNG/WebP images, maximum 5 MB each.',saveDelivery:'Complete delivery',
      refresh:'Refresh',sample:'Use sample ready trade',simulated:'SIMULATED',noTransporter:'No verified transporter accounts are available yet.',
      vehicleRequired:'Vehicle reference is required before dispatch.',recipientRequired:'Recipient name is required.',tooMany:'Select no more than four proof-of-delivery images.',badFile:'Only JPEG, PNG or WebP images up to 5 MB are allowed.',
      assignmentSaved:'Transport assignment saved',jobAccepted:'Shipment accepted',dispatched:'Shipment dispatched',deliverySaved:'Delivery confirmed',
      localNotice:'Local mode preserves workflow state on this device only. No vehicle, transporter or delivery evidence shown here should be treated as a live shipment.',
      operationalNotice:'Live assignment requires an approved field-agent/admin account; shipment actions require the assigned transporter or admin.',
      transporterName:'Demo Transporter',pickupToday:'Today',proofCount:'proof image(s)',measured:'QC weight',agreed:'Agreed quantity',close:'Close'
    },
    bn:{
      kicker:'লজিস্টিকস',title:'ডিসপ্যাচ ও ডেলিভারি',sub:'পরিবহন নির্ধারণ, পিকআপ নিশ্চিত এবং যাচাইযোগ্য ডেলিভারি রেকর্ড সংরক্ষণ করুন।',
      live:'লাইভ শেয়ার্ড ওয়ার্কফ্লো',local:'ওয়ার্কফ্লো পরীক্ষা · শুধু ডিভাইসে',restricted:'অপারেশনাল ভূমিকা প্রয়োজন',
      queue:'ডিসপ্যাচের জন্য প্রস্তুত',queueSub:'QC পাস করা এবং পরিবহন নির্ধারণের অপেক্ষায় থাকা লেনদেন।',shipments:'শিপমেন্ট',shipmentsSub:'নির্ধারণ, ডিসপ্যাচ অবস্থা এবং ডেলিভারি নিশ্চিতকরণ।',
      emptyQueue:'পরিবহন নির্ধারণের অপেক্ষায় কোনো লেনদেন নেই।',emptyShipments:'এখনো কোনো শিপমেন্ট নেই।',
      route:'রুট',commodity:'পণ্য',dispatchQty:'ডিসপ্যাচ পরিমাণ',due:'ডেলিভারির সময়',assign:'পরিবহন নির্ধারণ',
      transporter:'পরিবহনকারী',vehicle:'যানবাহন রেফারেন্স',cost:'পরিবহন খরচ (টাকা)',pickup:'পিকআপ সময়',notes:'নির্ধারণের নোট',createAssignment:'নির্ধারণ তৈরি করুন',
      assigned:'নির্ধারিত',accepted:'গৃহীত',inTransit:'পথে আছে',delivered:'ডেলিভারি হয়েছে',cancelled:'বাতিল',
      acceptJob:'কাজ গ্রহণ করুন',dispatch:'ডিসপ্যাচ হয়েছে',deliver:'ডেলিভারি নিশ্চিত করুন',viewOnly:'শুধু অবস্থা',
      recipient:'গ্রহণকারীর নাম',deliveryNotes:'ডেলিভারি নোট',evidence:'ডেলিভারির প্রমাণ',evidenceHelp:'সর্বোচ্চ ৪টি JPEG/PNG/WebP ছবি, প্রতিটি সর্বোচ্চ ৫ MB।',saveDelivery:'ডেলিভারি সম্পন্ন করুন',
      refresh:'রিফ্রেশ',sample:'নমুনা প্রস্তুত লেনদেন ব্যবহার করুন',simulated:'সিমুলেটেড',noTransporter:'এখনো কোনো যাচাইকৃত পরিবহনকারী অ্যাকাউন্ট নেই।',
      vehicleRequired:'ডিসপ্যাচের আগে যানবাহন রেফারেন্স প্রয়োজন।',recipientRequired:'গ্রহণকারীর নাম প্রয়োজন।',tooMany:'সর্বোচ্চ চারটি ডেলিভারি প্রমাণের ছবি নির্বাচন করুন।',badFile:'শুধু JPEG, PNG বা WebP ছবি, সর্বোচ্চ ৫ MB, ব্যবহার করা যাবে।',
      assignmentSaved:'পরিবহন নির্ধারণ সংরক্ষিত হয়েছে',jobAccepted:'শিপমেন্ট গৃহীত হয়েছে',dispatched:'শিপমেন্ট ডিসপ্যাচ হয়েছে',deliverySaved:'ডেলিভারি নিশ্চিত হয়েছে',
      localNotice:'লোকাল মোডের অবস্থা শুধু এই ডিভাইসে থাকে। এখানে দেখানো যানবাহন, পরিবহনকারী বা ডেলিভারি প্রমাণকে লাইভ শিপমেন্ট হিসেবে ধরা যাবে না।',
      operationalNotice:'লাইভ নির্ধারণের জন্য অনুমোদিত ফিল্ড-এজেন্ট/অ্যাডমিন এবং শিপমেন্ট পরিচালনার জন্য নির্ধারিত পরিবহনকারী বা অ্যাডমিন প্রয়োজন।',
      transporterName:'ডেমো পরিবহনকারী',pickupToday:'আজ',proofCount:'টি প্রমাণের ছবি',measured:'QC ওজন',agreed:'সম্মত পরিমাণ',close:'বন্ধ করুন'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function role(){return profile()?.role||'';}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token());}
  function canAssign(){return liveReady()&&['field_agent','admin'].includes(role());}
  function canOperate(){return liveReady()&&['transporter','admin'].includes(role());}
  function uid(){return window.crypto?.randomUUID?.()||('local-'+Date.now()+'-'+Math.random().toString(16).slice(2));}
  function read(key){try{return JSON.parse(localStorage.getItem(key)||'[]');}catch{return [];}}
  function write(key,rows){localStorage.setItem(key,JSON.stringify(rows.slice(0,100)));}
  function dateLabel(v){if(!v)return '—';try{return new Intl.DateTimeFormat(lang()==='bn'?'bn-BD':'en-GB',{day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}).format(new Date(v));}catch{return String(v);}}
  function kg(v){return Number(v||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:1})+' kg';}
  function statusLabel(s){return ({assigned:t('assigned'),accepted:t('accepted'),in_transit:t('inTransit'),delivered:t('delivered'),cancelled:t('cancelled')})[s]||s;}

  async function rpc(name,body={}){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body)});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  function localReady(){
    const existing=new Set(read(SHIPMENT_KEY).filter(x=>x.status!=='cancelled').map(x=>x.tradeId));
    const rows=read(TRADE_KEY).filter(x=>x.status==='confirmed'&&x.tradeStatus==='ready_for_dispatch'&&x.tradeId&&!existing.has(x.tradeId)).map(x=>({
      trade_id:x.tradeId,confirmation_reference:x.reference,commodity_code:String(x.commodity||'Potato').toUpperCase(),commodity_name_en:x.commodity||'Potato',commodity_name_bn:x.commodity==='Rice'?'চাল':x.commodity==='Onion'?'পেঁয়াজ':'আলু',origin_district:x.origin||'Bogra',destination_district:x.destination||'Dhaka',agreed_quantity_kg:Number(x.quantityKg||0),dispatch_quantity_kg:Number(x.quantityKg||0),delivery_due_at:x.deliveryDue,source:'local'
    }));
    if(!rows.length&&!existing.has('TR-DEMO-LOG-001'))rows.push({trade_id:'TR-DEMO-LOG-001',confirmation_reference:'AX-DEMO-LOG-001',commodity_code:'POTATO',commodity_name_en:'Potato',commodity_name_bn:'আলু',origin_district:'Bogra',destination_district:'Dhaka',agreed_quantity_kg:5000,dispatch_quantity_kg:4880,delivery_due_at:new Date(Date.now()+86400000).toISOString(),source:'demo'});
    return rows;
  }

  function localShipments(){return read(SHIPMENT_KEY);}

  async function refresh(){
    localize();
    try{
      if(canAssign()){
        [readyRows,transporters]=await Promise.all([rpc('get_dispatch_queue'),rpc('get_available_transporters')]);
      }else if(!liveReady()){
        readyRows=localReady();transporters=[{profile_id:'DEMO-TRANSPORTER',display_name:t('transporterName'),verified:true}];
      }else{readyRows=[];transporters=[];}
      shipmentRows=liveReady()?await rpc('get_my_shipments'):localShipments();
      renderQueue();renderShipments();
    }catch(err){console.error(err);showError(err.message||'Could not load logistics workflow.');}
  }

  function injectView(){
    if(document.getElementById('logistics'))return;
    const main=document.querySelector('main.content');if(!main)return;
    const section=document.createElement('section');section.id='logistics';section.className='view';
    section.innerHTML=`<div class="page-heading"><div><div class="breadcrumb" data-log-key="kicker"></div><h1 data-log-key="title"></h1><p data-log-key="sub"></p></div><div class="heading-actions"><button id="logRefresh" class="button secondary" type="button" data-log-key="refresh"></button></div></div>
      <div id="logModeNote" class="log-mode-note"></div>
      <section class="card log-card"><div class="log-card-head"><div><h2 data-log-key="queue"></h2><p data-log-key="queueSub"></p></div><span id="logMode" class="log-mode"></span></div><div id="dispatchQueue" class="log-list"></div></section>
      <section class="card log-card"><div class="log-card-head"><div><h2 data-log-key="shipments"></h2><p data-log-key="shipmentsSub"></p></div></div><div id="shipmentList" class="log-list"></div></section>`;
    main.appendChild(section);document.getElementById('logRefresh').addEventListener('click',refresh);wireNav();localize();refresh();
  }

  function wireNav(){
    const old=document.querySelector('[data-i18n="nav_logistics"]')?.closest('.side-link');if(!old)return;
    const btn=old.cloneNode(true);btn.removeAttribute('data-action');btn.dataset.view='logistics';old.replaceWith(btn);btn.addEventListener('click',showView);
  }

  function showView(){
    document.querySelectorAll('.view').forEach(v=>v.classList.remove('active-view'));document.getElementById('logistics')?.classList.add('active-view');
    document.querySelectorAll('.side-link[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view==='logistics'));
    document.querySelector('.sidebar')?.classList.remove('open');document.getElementById('mobileOverlay')?.classList.remove('show');window.scrollTo({top:0,behavior:'smooth'});refresh();
  }

  function localize(){
    document.querySelectorAll('#logistics [data-log-key],#logAssignModal [data-log-key],#logDeliveryModal [data-log-key]').forEach(el=>{el.textContent=t(el.dataset.logKey);});
    const mode=document.getElementById('logMode');if(mode){mode.textContent=liveReady()?t('live'):t('local');mode.className='log-mode '+(liveReady()?'is-live':'is-local');}
    const note=document.getElementById('logModeNote');if(note)note.textContent=liveReady()?t('operationalNotice'):t('localNotice');
  }

  function renderQueue(){
    const target=document.getElementById('dispatchQueue');if(!target)return;
    if(!readyRows.length){target.innerHTML=`<div class="log-empty">${t('emptyQueue')}</div>`;return;}
    target.innerHTML=readyRows.map((x,i)=>`<article class="log-row"><div class="log-main"><span class="log-ref">${esc(x.confirmation_reference||x.trade_id)}</span><strong>${esc(lang()==='bn'?(x.commodity_name_bn||x.commodity_name_en):(x.commodity_name_en||x.commodity_code))}</strong><span>${esc(x.origin_district)} → ${esc(x.destination_district)}</span></div><div><span>${t('agreed')}</span><strong>${kg(x.agreed_quantity_kg)}</strong></div><div><span>${t('measured')}</span><strong>${kg(x.dispatch_quantity_kg)}</strong></div><div><span>${t('due')}</span><strong>${dateLabel(x.delivery_due_at)}</strong></div><button class="button primary log-assign" data-index="${i}" type="button">${t('assign')}</button></article>`).join('');
    target.querySelectorAll('.log-assign').forEach(b=>b.addEventListener('click',()=>openAssign(readyRows[Number(b.dataset.index)])));
  }

  function actionButton(s,i){
    if(liveReady()&&!canOperate())return `<span class="log-readonly">${t('viewOnly')}</span>`;
    if(s.status==='assigned')return `<button class="button secondary log-action" data-act="accept" data-index="${i}">${t('acceptJob')}</button>`;
    if(s.status==='accepted')return `<button class="button primary log-action" data-act="dispatch" data-index="${i}">${t('dispatch')}</button>`;
    if(s.status==='in_transit')return `<button class="button primary log-action" data-act="deliver" data-index="${i}">${t('deliver')}</button>`;
    return '';
  }

  function normalizeShipment(x){return {id:x.shipment_id||x.id,status:x.shipment_status||x.status,tradeId:x.trade_id||x.tradeId,reference:x.confirmation_reference||x.reference,commodityEn:x.commodity_name_en||x.commodityEn||'Potato',commodityBn:x.commodity_name_bn||x.commodityBn||'আলু',origin:x.origin_district||x.origin||'Bogra',destination:x.destination_district||x.destination||'Dhaka',quantity:Number(x.measured_quantity_kg||x.quantity||0),vehicle:x.vehicle_reference||x.vehicle||'',cost:x.transport_cost_bdt??x.cost,transporter:x.transporter_name||x.transporter||t('transporterName'),pickupDue:x.pickup_due_at||x.pickupDue,assignedAt:x.assigned_at||x.assignedAt,dispatchedAt:x.dispatched_at||x.dispatchedAt,deliveredAt:x.delivered_at||x.deliveredAt,recipient:x.recipient_name||x.recipient||'',source:x.source||'supabase'};}

  function renderShipments(){
    const target=document.getElementById('shipmentList');if(!target)return;
    const rows=shipmentRows.map(normalizeShipment);
    if(!rows.length){target.innerHTML=`<div class="log-empty">${t('emptyShipments')}</div>`;return;}
    target.innerHTML=rows.map((s,i)=>`<article class="shipment-row"><div class="log-main"><span class="log-ref">${esc(s.reference||s.id)}</span><strong>${esc(lang()==='bn'?s.commodityBn:s.commodityEn)}</strong><span>${esc(s.origin)} → ${esc(s.destination)}</span></div><div><span>${t('transporter')}</span><strong>${esc(s.transporter||'—')}</strong></div><div><span>${t('vehicle')}</span><strong>${esc(s.vehicle||'—')}</strong></div><div><span>${t('status')}</span><strong class="ship-status ${esc(s.status)}">${statusLabel(s.status)}</strong></div><div class="log-row-action">${actionButton(s,i)}</div></article>`).join('');
    target.querySelectorAll('.log-action').forEach(b=>b.addEventListener('click',()=>handleAction(rows[Number(b.dataset.index)],b.dataset.act)));
  }

  function injectAssign(){
    if(document.getElementById('logAssignModal'))return;
    const m=document.createElement('div');m.id='logAssignModal';m.className='log-modal';m.innerHTML=`<div class="log-backdrop" data-log-close></div><section class="log-sheet"><button class="log-close" data-log-close type="button">×</button><div class="log-brand">Agro-Exchange</div><div class="section-kicker" data-log-key="kicker"></div><h2 data-log-key="assign"></h2><div id="assignSummary" class="log-summary"></div><form id="assignForm" class="log-form"><label><span data-log-key="transporter"></span><select name="transporter" required></select></label><label><span data-log-key="vehicle"></span><input name="vehicle" type="text" maxlength="60"></label><label><span data-log-key="cost"></span><input name="cost" type="number" min="0" step="1" inputmode="decimal"></label><label><span data-log-key="pickup"></span><input name="pickup" type="datetime-local"></label><label class="log-wide"><span data-log-key="notes"></span><textarea name="notes" maxlength="400"></textarea></label><button class="button primary log-wide" type="submit" data-log-key="createAssignment"></button></form></section>`;
    document.body.appendChild(m);m.querySelectorAll('[data-log-close]').forEach(x=>x.addEventListener('click',()=>m.classList.remove('open')));document.getElementById('assignForm').addEventListener('submit',submitAssign);localize();
  }

  function openAssign(row){
    injectAssign();activeTrade=row;const form=document.getElementById('assignForm');form.reset();
    const select=form.elements.transporter;select.innerHTML=transporters.length?transporters.map(x=>`<option value="${esc(x.profile_id)}">${esc(x.display_name)}</option>`).join(''):`<option value="">${t('noTransporter')}</option>`;
    const d=new Date(Date.now()+4*3600000);d.setMinutes(d.getMinutes()-d.getTimezoneOffset());form.elements.pickup.value=d.toISOString().slice(0,16);
    document.getElementById('assignSummary').innerHTML=`<div><span>${t('route')}</span><strong>${esc(row.origin_district)} → ${esc(row.destination_district)}</strong></div><div><span>${t('dispatchQty')}</span><strong>${kg(row.dispatch_quantity_kg)}</strong></div>`;
    document.getElementById('logAssignModal').classList.add('open');
  }

  function updateLocalTradeStatus(tradeId,status){const rows=read(TRADE_KEY);const row=rows.find(x=>x.tradeId===tradeId);if(row){row.tradeStatus=status;write(TRADE_KEY,rows);}}

  async function submitAssign(e){
    e.preventDefault();const f=e.currentTarget;const transporter=String(f.elements.transporter.value||'');if(!transporter){toast?.(t('noTransporter'));return;}
    const cost=f.elements.cost.value===''?null:Number(f.elements.cost.value);const pickup=f.elements.pickup.value?new Date(f.elements.pickup.value).toISOString():null;
    try{
      if(canAssign())await rpc('assign_shipment',{p_trade_id:activeTrade.trade_id,p_transporter_profile_id:transporter,p_vehicle_reference:String(f.elements.vehicle.value||'')||null,p_transport_cost_bdt:cost,p_pickup_due_at:pickup,p_notes:String(f.elements.notes.value||'')||null});
      else{
        const rows=read(SHIPMENT_KEY);rows.unshift({id:uid(),tradeId:activeTrade.trade_id,reference:activeTrade.confirmation_reference,commodityEn:activeTrade.commodity_name_en,commodityBn:activeTrade.commodity_name_bn,origin:activeTrade.origin_district,destination:activeTrade.destination_district,quantity:Number(activeTrade.dispatch_quantity_kg),vehicle:String(f.elements.vehicle.value||''),cost,transporter:t('transporterName'),pickupDue:pickup,assignedAt:new Date().toISOString(),status:'assigned',source:'local'});write(SHIPMENT_KEY,rows);
      }
      document.getElementById('logAssignModal').classList.remove('open');if(typeof toast==='function')toast(t('assignmentSaved'));await refresh();
    }catch(err){if(typeof toast==='function')toast(err.message||'Assignment failed.');}
  }

  async function handleAction(s,act){
    try{
      if(act==='accept'){
        if(canOperate())await rpc('accept_shipment',{p_shipment_id:s.id});else localMutate(s.id,x=>{x.status='accepted';x.acceptedAt=new Date().toISOString();});
        if(typeof toast==='function')toast(t('jobAccepted'));
      }else if(act==='dispatch'){
        let vehicle=s.vehicle;if(!vehicle)vehicle=window.prompt(t('vehicle'))||'';if(!vehicle.trim()){if(typeof toast==='function')toast(t('vehicleRequired'));return;}
        if(canOperate())await rpc('dispatch_shipment',{p_shipment_id:s.id,p_vehicle_reference:vehicle.trim()});else{localMutate(s.id,x=>{x.status='in_transit';x.vehicle=vehicle.trim();x.dispatchedAt=new Date().toISOString();});updateLocalTradeStatus(s.tradeId,'in_transit');}
        if(typeof toast==='function')toast(t('dispatched'));
      }else if(act==='deliver')openDelivery(s);
      await refresh();
    }catch(err){if(typeof toast==='function')toast(err.message||'Logistics action failed.');}
  }

  function localMutate(id,fn){const rows=read(SHIPMENT_KEY);const row=rows.find(x=>x.id===id);if(row){fn(row);write(SHIPMENT_KEY,rows);}}

  function injectDelivery(){
    if(document.getElementById('logDeliveryModal'))return;
    const m=document.createElement('div');m.id='logDeliveryModal';m.className='log-modal';m.innerHTML=`<div class="log-backdrop" data-del-close></div><section class="log-sheet"><button class="log-close" data-del-close type="button">×</button><div class="log-brand">Agro-Exchange</div><div class="section-kicker" data-log-key="kicker"></div><h2 data-log-key="deliver"></h2><div id="deliverySummary" class="log-summary"></div><form id="deliveryForm" class="log-form"><label class="log-wide"><span data-log-key="recipient"></span><input name="recipient" type="text" maxlength="120" required></label><label class="log-wide"><span data-log-key="deliveryNotes"></span><textarea name="notes" maxlength="500"></textarea></label><label class="log-wide"><span data-log-key="evidence"></span><input id="deliveryEvidence" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" multiple><small data-log-key="evidenceHelp"></small></label><div id="deliveryFiles" class="log-files log-wide"></div><button class="button primary log-wide" type="submit" data-log-key="saveDelivery"></button></form></section>`;
    document.body.appendChild(m);m.querySelectorAll('[data-del-close]').forEach(x=>x.addEventListener('click',()=>m.classList.remove('open')));document.getElementById('deliveryEvidence').addEventListener('change',e=>{deliveryFiles=Array.from(e.target.files||[]);document.getElementById('deliveryFiles').innerHTML=deliveryFiles.map(f=>`<span>${esc(f.name)} · ${(f.size/1024/1024).toFixed(1)} MB</span>`).join('');});document.getElementById('deliveryForm').addEventListener('submit',submitDelivery);localize();
  }

  function openDelivery(s){injectDelivery();activeShipment=s;deliveryFiles=[];const f=document.getElementById('deliveryForm');f.reset();document.getElementById('deliveryFiles').innerHTML='';document.getElementById('deliverySummary').innerHTML=`<div><span>${t('route')}</span><strong>${esc(s.origin)} → ${esc(s.destination)}</strong></div><div><span>${t('vehicle')}</span><strong>${esc(s.vehicle||'—')}</strong></div>`;document.getElementById('logDeliveryModal').classList.add('open');}

  function validateFiles(){if(deliveryFiles.length>4)throw new Error(t('tooMany'));for(const f of deliveryFiles){if(!['image/jpeg','image/png','image/webp'].includes(f.type)||f.size>5242880)throw new Error(t('badFile'));}}
  function safeFile(name){return String(name||'delivery').replace(/[^A-Za-z0-9._-]+/g,'-').slice(-90);}
  async function upload(file){const path=activeShipment.tradeId+'/'+uid()+'-'+safeFile(file.name);const encoded=path.split('/').map(encodeURIComponent).join('/');const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/storage/v1/object/delivery-evidence/'+encoded,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':file.type,'x-upsert':'false'},body:file});const text=await r.text();if(!r.ok)throw new Error(text||'Proof upload failed');return path;}

  async function submitDelivery(e){
    e.preventDefault();const f=e.currentTarget;const recipient=String(f.elements.recipient.value||'').trim();if(!recipient){if(typeof toast==='function')toast(t('recipientRequired'));return;}
    try{validateFiles();const evidence=[];if(canOperate())for(const file of deliveryFiles)evidence.push(await upload(file));
      if(canOperate())await rpc('complete_shipment_delivery',{p_shipment_id:activeShipment.id,p_recipient_name:recipient,p_notes:String(f.elements.notes.value||'')||null,p_evidence_objects:evidence});
      else{localMutate(activeShipment.id,x=>{x.status='delivered';x.deliveredAt=new Date().toISOString();x.recipient=recipient;x.deliveryNotes=String(f.elements.notes.value||'');x.evidence=deliveryFiles.map(file=>({name:file.name,type:file.type,size:file.size,localOnly:true}));});updateLocalTradeStatus(activeShipment.tradeId,'delivered');}
      document.getElementById('logDeliveryModal').classList.remove('open');if(typeof toast==='function')toast(t('deliverySaved'));await refresh();
    }catch(err){if(typeof toast==='function')toast(err.message||'Delivery confirmation failed.');}
  }

  function showError(msg){const q=document.getElementById('dispatchQueue');if(q)q.innerHTML=`<div class="log-empty">${esc(msg)}</div>`;}

  function init(){const css=document.createElement('link');css.rel='stylesheet';css.href='backend/logistics-workflow.css';document.head.appendChild(css);injectView();document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{localize();refresh();},0));window.addEventListener('agro-auth-changed',()=>setTimeout(refresh,0));}

  window.AgroLogistics={refresh,show:showView};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
