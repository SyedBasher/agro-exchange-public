(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const LOCAL_QC_KEY='agro_exchange_qc_records_v1';
  const LOCAL_TRADES_KEY='agro_exchange_trade_confirmations_v1';
  let activeTrade=null;
  let selectedFiles=[];

  const copy={
    en:{
      kicker:'QUALITY CONTROL',title:'QC & certified weight',sub:'Record measured weight, accepted grade and evidence before a confirmed trade is released for dispatch.',
      modeLive:'Live QC operator',modeLocal:'Workflow test · device only',modeDenied:'QC operator access required',
      queue:'QC queue',queueSub:'Confirmed trades requiring quality and weight verification.',empty:'No trades are currently waiting for QC.',
      trade:'Trade',route:'Route',commodity:'Commodity',agreed:'Agreed quantity',due:'Delivery due',status:'Status',inspect:'Start QC',
      demo:'Use sample confirmed trade',review:'Record QC result',measured:'Measured weight (kg)',grade:'Accepted grade code',method:'Weighing method',
      digital:'Digital platform scale',warehouse:'Warehouse scale',other:'Other scale',certified:'Scale certification verified',scaleRef:'Scale / certificate reference',
      decision:'QC decision',accept:'Accept for dispatch',reject:'Reject / send to dispute',notes:'Operator notes',photos:'Photo evidence',photosHelp:'Up to 4 JPEG/PNG/WebP images, maximum 5 MB each.',
      save:'Save QC result',close:'Close',variance:'Weight variance',evidence:'Evidence',ready:'Ready for dispatch',disputed:'Disputed',awaiting:'Awaiting QC',confirmed:'Confirmed',
      saved:'QC result saved',localEvidence:'In workflow-test mode, image names are recorded locally but files are not uploaded.',certifiedLabel:'Certified scale',uncertifiedLabel:'Certification not recorded',
      badWeight:'Measured weight must be greater than zero.',needRef:'Enter the scale/certificate reference when certification is verified.',tooMany:'Select no more than four evidence images.',badFile:'Only JPEG, PNG or WebP images up to 5 MB are allowed.',
      noOperator:'Sign in with an approved QC-operator or admin account to use the shared database workflow.',simulated:'SIMULATED',recorded:'Recorded',
      refresh:'Refresh queue',qcPassed:'QC accepted',qcRejected:'QC rejected',photoCount:'photo(s)'
    },
    bn:{
      kicker:'মান নিয়ন্ত্রণ',title:'QC ও যাচাইকৃত ওজন',sub:'নিশ্চিত লেনদেন পাঠানোর আগে পরিমাপ করা ওজন, গৃহীত গ্রেড ও প্রমাণ নথিবদ্ধ করুন।',
      modeLive:'লাইভ QC অপারেটর',modeLocal:'ওয়ার্কফ্লো পরীক্ষা · শুধু ডিভাইসে',modeDenied:'QC অপারেটর অনুমোদন প্রয়োজন',
      queue:'QC তালিকা',queueSub:'মান ও ওজন যাচাইয়ের অপেক্ষায় থাকা নিশ্চিত লেনদেন।',empty:'এখন কোনো লেনদেন QC-এর অপেক্ষায় নেই।',
      trade:'লেনদেন',route:'রুট',commodity:'পণ্য',agreed:'সম্মত পরিমাণ',due:'ডেলিভারির সময়',status:'অবস্থা',inspect:'QC শুরু করুন',
      demo:'নমুনা নিশ্চিত লেনদেন ব্যবহার করুন',review:'QC ফলাফল নথিবদ্ধ করুন',measured:'পরিমাপ করা ওজন (কেজি)',grade:'গৃহীত গ্রেড কোড',method:'ওজন পদ্ধতি',
      digital:'ডিজিটাল প্ল্যাটফর্ম স্কেল',warehouse:'গুদাম স্কেল',other:'অন্যান্য স্কেল',certified:'স্কেল সার্টিফিকেশন যাচাই করা হয়েছে',scaleRef:'স্কেল / সনদ রেফারেন্স',
      decision:'QC সিদ্ধান্ত',accept:'পাঠানোর জন্য গ্রহণ',reject:'প্রত্যাখ্যান / বিরোধে পাঠান',notes:'অপারেটরের নোট',photos:'ছবির প্রমাণ',photosHelp:'সর্বোচ্চ ৪টি JPEG/PNG/WebP ছবি, প্রতিটি সর্বোচ্চ ৫ MB।',
      save:'QC ফলাফল সংরক্ষণ',close:'বন্ধ করুন',variance:'ওজনের পার্থক্য',evidence:'প্রমাণ',ready:'পাঠানোর জন্য প্রস্তুত',disputed:'বিরোধাধীন',awaiting:'QC-এর অপেক্ষায়',confirmed:'নিশ্চিত',
      saved:'QC ফলাফল সংরক্ষিত হয়েছে',localEvidence:'ওয়ার্কফ্লো পরীক্ষা মোডে ছবির নাম স্থানীয়ভাবে নথিবদ্ধ হয়, ফাইল আপলোড হয় না।',certifiedLabel:'সার্টিফায়েড স্কেল',uncertifiedLabel:'সার্টিফিকেশন নথিবদ্ধ নয়',
      badWeight:'পরিমাপ করা ওজন শূন্যের বেশি হতে হবে।',needRef:'সার্টিফিকেশন যাচাই করা হলে স্কেল/সনদ রেফারেন্স দিন।',tooMany:'সর্বোচ্চ চারটি প্রমাণের ছবি নির্বাচন করুন।',badFile:'শুধু JPEG, PNG বা WebP ছবি, সর্বোচ্চ ৫ MB, ব্যবহার করা যাবে।',
      noOperator:'শেয়ার্ড ডেটাবেজ ওয়ার্কফ্লোর জন্য অনুমোদিত QC অপারেটর বা অ্যাডমিন হিসেবে সাইন ইন করুন।',simulated:'সিমুলেটেড',recorded:'নথিবদ্ধ',
      refresh:'তালিকা রিফ্রেশ',qcPassed:'QC গৃহীত',qcRejected:'QC প্রত্যাখ্যাত',photoCount:'টি ছবি'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>'\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','\"':'&quot;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token()&&['qc_operator','admin'].includes(profile()?.role));}
  function signedInButDenied(){return Boolean(token()&&!['qc_operator','admin'].includes(profile()?.role));}
  function uid(){return window.crypto?.randomUUID?.()||('local-'+Date.now()+'-'+Math.random().toString(16).slice(2));}
  function readJson(key){try{return JSON.parse(localStorage.getItem(key)||'[]');}catch{return [];}}
  function writeJson(key,rows){localStorage.setItem(key,JSON.stringify(rows.slice(0,100)));}
  function fmtDate(v){if(!v)return '—';try{return new Intl.DateTimeFormat(lang()==='bn'?'bn-BD':'en-GB',{day:'numeric',month:'short'}).format(new Date(v));}catch{return String(v).slice(0,10);}}
  function fmtKg(v){return Number(v||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:1})+' kg';}

  async function rpc(name,body={}){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/'+name,{
      method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body)
    });
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  function localQcRows(){return readJson(LOCAL_QC_KEY);}
  function localTradeRows(){return readJson(LOCAL_TRADES_KEY);}

  function demoTrade(){return {
    trade_id:'TR-DEMO-QC-001',confirmation_reference:'AX-DEMO-QC-001',commodity_code:'POTATO',commodity_name_en:'Potato',commodity_name_bn:'আলু',grade_code:'A',
    origin_district:'Bogra',destination_district:'Dhaka',agreed_quantity_kg:5000,agreed_price_bdt_per_kg:31.5,delivery_due_at:new Date(Date.now()+2*86400000).toISOString(),trade_status:'confirmed',qc_required:true,source:'demo'
  };}

  function localQueue(){
    const done=new Set(localQcRows().map(x=>x.tradeId));
    const rows=localTradeRows().filter(x=>x.status==='confirmed'&&x.qcRequired!==false&&x.tradeId&&!done.has(x.tradeId)).map(x=>({
      trade_id:x.tradeId,confirmation_reference:x.reference,commodity_code:(x.commodity||'Potato').toUpperCase(),commodity_name_en:x.commodity||'Potato',commodity_name_bn:x.commodity==='Rice'?'চাল':x.commodity==='Onion'?'পেঁয়াজ':'আলু',grade_code:x.commodity==='Rice'?'STD':'A',
      origin_district:x.origin||'Bogra',destination_district:x.destination||'Dhaka',agreed_quantity_kg:Number(x.quantityKg||0),agreed_price_bdt_per_kg:Number(x.price||0),delivery_due_at:x.deliveryDue,trade_status:x.tradeStatus||'confirmed',qc_required:true,source:'local'
    }));
    if(!rows.length&&!done.has('TR-DEMO-QC-001'))rows.push(demoTrade());
    return rows;
  }

  async function loadQueue(){
    if(liveReady())return await rpc('get_qc_queue');
    return localQueue();
  }

  function injectView(){
    if(document.getElementById('quality'))return;
    const main=document.querySelector('main.content');if(!main)return;
    const section=document.createElement('section');section.id='quality';section.className='view';
    section.innerHTML=`<div class="page-heading"><div><div class="breadcrumb" data-qc-key="kicker"></div><h1 data-qc-key="title"></h1><p data-qc-key="sub"></p></div><div class="heading-actions"><button id="qcRefresh" class="button secondary" type="button" data-qc-key="refresh"></button></div></div>
      <section class="card qc-queue-card"><div class="qc-head"><div><h2 data-qc-key="queue"></h2><p data-qc-key="queueSub"></p></div><span id="qcMode" class="qc-mode"></span></div><div id="qcAccessNote" class="qc-access-note"></div><div id="qcQueue" class="qc-queue"></div></section>
      <section class="card qc-history-card"><div class="qc-head"><div><h2>${lang()==='bn'?'সাম্প্রতিক QC রেকর্ড':'Recent QC records'}</h2></div></div><div id="qcHistory" class="qc-history"></div></section>`;
    main.appendChild(section);
    document.getElementById('qcRefresh').addEventListener('click',refresh);
    wireNav();localize();refresh();
  }

  function wireNav(){
    const old=document.querySelector('[data-i18n="nav_quality"]')?.closest('.side-link');if(!old)return;
    const btn=old.cloneNode(true);btn.removeAttribute('data-action');btn.dataset.view='quality';old.replaceWith(btn);
    btn.addEventListener('click',()=>showView());
  }

  function showView(){
    document.querySelectorAll('.view').forEach(v=>v.classList.remove('active-view'));
    document.getElementById('quality')?.classList.add('active-view');
    document.querySelectorAll('.side-link[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view==='quality'));
    document.querySelector('.sidebar')?.classList.remove('open');document.getElementById('mobileOverlay')?.classList.remove('show');
    window.scrollTo({top:0,behavior:'smooth'});refresh();
  }

  function localize(){
    document.querySelectorAll('#quality [data-qc-key],#qcModal [data-qc-key]').forEach(el=>{el.textContent=t(el.dataset.qcKey);});
    const mode=document.getElementById('qcMode');if(mode){mode.textContent=liveReady()?t('modeLive'):signedInButDenied()?t('modeDenied'):t('modeLocal');mode.className='qc-mode '+(liveReady()?'is-live':signedInButDenied()?'is-denied':'is-local');}
    const note=document.getElementById('qcAccessNote');if(note)note.textContent=signedInButDenied()?t('noOperator'):(!liveReady()?t('localEvidence'):'');
  }

  async function refresh(){
    localize();
    const q=document.getElementById('qcQueue');if(q)q.innerHTML='<div class="qc-loading">…</div>';
    try{renderQueue(await loadQueue());}catch(err){if(q)q.innerHTML=`<div class="qc-empty">${esc(err.message)}</div>`;}
    renderHistory();
  }

  function renderQueue(rows){
    const target=document.getElementById('qcQueue');if(!target)return;
    if(!rows?.length){target.innerHTML=`<div class="qc-empty">${t('empty')}</div>`;return;}
    target.innerHTML=rows.map((x,i)=>`<article class="qc-row">
      <div class="qc-row-main"><span class="qc-ref">${esc(x.confirmation_reference||x.trade_id)}</span><strong>${esc(lang()==='bn'?(x.commodity_name_bn||x.commodity_name_en):(x.commodity_name_en||x.commodity_code))}</strong><span>${esc(x.origin_district)} → ${esc(x.destination_district)}</span></div>
      <div><span>${t('agreed')}</span><strong>${fmtKg(x.agreed_quantity_kg)}</strong></div>
      <div><span>${t('due')}</span><strong>${fmtDate(x.delivery_due_at)}</strong></div>
      <div><span>${t('status')}</span><strong>${x.trade_status==='awaiting_qc'?t('awaiting'):t('confirmed')}</strong></div>
      <button class="button primary qc-open" type="button" data-index="${i}">${t('inspect')}</button>
    </article>`).join('');
    target.querySelectorAll('.qc-open').forEach(btn=>btn.addEventListener('click',()=>openQc(rows[Number(btn.dataset.index)])));
  }

  function injectModal(){
    if(document.getElementById('qcModal'))return;
    const m=document.createElement('div');m.id='qcModal';m.className='qc-modal';m.setAttribute('aria-hidden','true');
    m.innerHTML=`<div class="qc-backdrop" data-qc-close></div><section class="qc-sheet" role="dialog" aria-modal="true" aria-labelledby="qcModalTitle"><button class="qc-close" type="button" data-qc-close>×</button><div class="qc-brand">Agro-Exchange</div><div class="section-kicker" data-qc-key="kicker"></div><h2 id="qcModalTitle" data-qc-key="review"></h2><div id="qcTradeSummary" class="qc-summary"></div>
      <form id="qcForm" class="qc-form">
        <label><span data-qc-key="measured"></span><input name="weight" type="number" inputmode="decimal" min="0.1" step="0.1" required></label>
        <label><span data-qc-key="grade"></span><input name="grade" type="text" maxlength="20"></label>
        <label><span data-qc-key="method"></span><select name="method"><option value="digital_scale" data-qc-key="digital"></option><option value="warehouse_scale" data-qc-key="warehouse"></option><option value="other" data-qc-key="other"></option></select></label>
        <label><span data-qc-key="decision"></span><select name="decision"><option value="accept" data-qc-key="accept"></option><option value="reject" data-qc-key="reject"></option></select></label>
        <label class="qc-wide qc-check"><input id="qcCertified" name="certified" type="checkbox"><span data-qc-key="certified"></span></label>
        <label class="qc-wide"><span data-qc-key="scaleRef"></span><input id="qcScaleRef" name="scaleRef" type="text" maxlength="120" disabled></label>
        <label class="qc-wide"><span data-qc-key="notes"></span><textarea name="notes" rows="3" maxlength="500"></textarea></label>
        <label class="qc-wide"><span data-qc-key="photos"></span><input id="qcPhotos" name="photos" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" multiple><small data-qc-key="photosHelp"></small></label>
        <div id="qcFileList" class="qc-file-list qc-wide"></div><div id="qcVariance" class="qc-variance qc-wide"></div>
        <button class="button primary qc-wide" type="submit" data-qc-key="save"></button>
      </form><div id="qcResult"></div></section>`;
    document.body.appendChild(m);m.querySelectorAll('[data-qc-close]').forEach(x=>x.addEventListener('click',closeQc));
    document.getElementById('qcCertified').addEventListener('change',e=>{document.getElementById('qcScaleRef').disabled=!e.target.checked;});
    document.getElementById('qcPhotos').addEventListener('change',filesChanged);
    document.getElementById('qcForm').addEventListener('input',updateVariance);
    document.getElementById('qcForm').addEventListener('submit',submitQc);
    localize();
  }

  function openQc(trade){
    injectModal();activeTrade=trade;selectedFiles=[];
    const form=document.getElementById('qcForm');form.reset();form.elements.weight.value=Number(trade.agreed_quantity_kg||0).toFixed(1);form.elements.grade.value=trade.grade_code||'';document.getElementById('qcScaleRef').disabled=true;document.getElementById('qcFileList').innerHTML='';document.getElementById('qcResult').innerHTML='';
    document.getElementById('qcTradeSummary').innerHTML=`<div><span>${t('trade')}</span><strong>${esc(trade.confirmation_reference||trade.trade_id)}</strong></div><div><span>${t('route')}</span><strong>${esc(trade.origin_district)} → ${esc(trade.destination_district)}</strong></div><div><span>${t('agreed')}</span><strong>${fmtKg(trade.agreed_quantity_kg)}</strong></div>`;
    updateVariance();const m=document.getElementById('qcModal');m.classList.add('open');m.setAttribute('aria-hidden','false');
  }
  function closeQc(){const m=document.getElementById('qcModal');if(m){m.classList.remove('open');m.setAttribute('aria-hidden','true');}}

  function filesChanged(e){
    selectedFiles=Array.from(e.target.files||[]);
    const list=document.getElementById('qcFileList');
    list.innerHTML=selectedFiles.map(f=>`<span>${esc(f.name)} · ${(f.size/1024/1024).toFixed(1)} MB</span>`).join('');
  }

  function updateVariance(){
    if(!activeTrade)return;const weight=Number(document.getElementById('qcForm')?.elements.weight.value||0);const agreed=Number(activeTrade.agreed_quantity_kg||0);const variance=agreed?100*(weight-agreed)/agreed:0;
    const el=document.getElementById('qcVariance');if(el)el.innerHTML=`<span>${t('variance')}</span><strong class="${Math.abs(variance)>2?'qc-warn':''}">${variance>=0?'+':''}${variance.toFixed(2)}%</strong>`;
  }

  function validate(form){
    const weight=Number(form.elements.weight.value);if(!Number.isFinite(weight)||weight<=0)throw new Error(t('badWeight'));
    if(form.elements.certified.checked&&!String(form.elements.scaleRef.value||'').trim())throw new Error(t('needRef'));
    if(selectedFiles.length>4)throw new Error(t('tooMany'));
    for(const f of selectedFiles){if(!['image/jpeg','image/png','image/webp'].includes(f.type)||f.size>5242880)throw new Error(t('badFile'));}
    return weight;
  }

  function safeFileName(name){return String(name||'evidence').replace(/[^A-Za-z0-9._-]+/g,'-').slice(-90);}
  async function uploadEvidence(tradeId,file){
    const path=tradeId+'/'+uid()+'-'+safeFileName(file.name);const encoded=path.split('/').map(encodeURIComponent).join('/');
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/storage/v1/object/qc-evidence/'+encoded,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':file.type,'x-upsert':'false'},body:file});
    const text=await r.text();if(!r.ok){let msg=text;try{msg=JSON.parse(text)?.message||text;}catch{}throw new Error(msg||'Evidence upload failed');}return path;
  }

  async function saveRemote(form,weight){
    await rpc('begin_trade_qc',{p_trade_id:activeTrade.trade_id});
    const evidence=[];for(const f of selectedFiles)evidence.push(await uploadEvidence(activeTrade.trade_id,f));
    const rows=await rpc('record_trade_qc',{
      p_trade_id:activeTrade.trade_id,p_measured_weight_kg:weight,p_accepted_grade_code:String(form.elements.grade.value||'').trim()||null,
      p_accepted:form.elements.decision.value==='accept',p_certified_scale:form.elements.certified.checked,p_scale_reference:String(form.elements.scaleRef.value||'').trim()||null,
      p_weighing_method:form.elements.method.value,p_notes:String(form.elements.notes.value||'').trim()||null,p_evidence_objects:evidence
    });
    return Array.isArray(rows)?rows[0]:rows;
  }

  function saveLocal(form,weight){
    const rows=localQcRows();const variance=Number(activeTrade.agreed_quantity_kg)?100*(weight-Number(activeTrade.agreed_quantity_kg))/Number(activeTrade.agreed_quantity_kg):0;const accepted=form.elements.decision.value==='accept';
    const row={id:uid(),tradeId:activeTrade.trade_id,confirmationReference:activeTrade.confirmation_reference,commodity:activeTrade.commodity_name_en||activeTrade.commodity_code,measuredWeightKg:weight,agreedWeightKg:Number(activeTrade.agreed_quantity_kg),acceptedGradeCode:String(form.elements.grade.value||''),accepted,certifiedScale:form.elements.certified.checked,scaleReference:String(form.elements.scaleRef.value||''),weighingMethod:form.elements.method.value,notes:String(form.elements.notes.value||''),evidence:selectedFiles.map(f=>({name:f.name,type:f.type,size:f.size,localOnly:true})),weightVariancePct:Number(variance.toFixed(2)),tradeStatus:accepted?'ready_for_dispatch':'disputed',recordedAt:new Date().toISOString()};
    rows.unshift(row);writeJson(LOCAL_QC_KEY,rows);
    const trades=localTradeRows();const tr=trades.find(x=>x.tradeId===activeTrade.trade_id);if(tr){tr.tradeStatus=row.tradeStatus;writeJson(LOCAL_TRADES_KEY,trades);}return {qc_record_id:row.id,trade_id:row.tradeId,trade_status:row.tradeStatus,weight_variance_pct:row.weightVariancePct,evidence_count:row.evidence.length};
  }

  async function submitQc(e){
    e.preventDefault();const form=e.currentTarget;const btn=form.querySelector('button[type="submit"]');btn.disabled=true;
    try{const weight=validate(form);const result=liveReady()?await saveRemote(form,weight):saveLocal(form,weight);renderResult(result);if(typeof toast==='function')toast(t('saved'));await refresh();}
    catch(err){console.error(err);if(typeof toast==='function')toast(err.message||'Could not save QC result.');}
    finally{btn.disabled=false;}
  }

  function renderResult(r){
    const target=document.getElementById('qcResult');if(!target)return;const ok=r.trade_status==='ready_for_dispatch';
    target.innerHTML=`<div class="qc-result ${ok?'is-pass':'is-reject'}"><strong>${ok?t('qcPassed'):t('qcRejected')}</strong><span>${t('variance')}: ${Number(r.weight_variance_pct||0)>=0?'+':''}${Number(r.weight_variance_pct||0).toFixed(2)}%</span><span>${t('evidence')}: ${Number(r.evidence_count||0)}</span><span>${ok?t('ready'):t('disputed')}</span></div>`;
  }

  function renderHistory(){
    const target=document.getElementById('qcHistory');if(!target)return;const rows=localQcRows().slice(0,8);
    if(!rows.length){target.innerHTML=`<div class="qc-empty">${t('empty')}</div>`;return;}
    target.innerHTML=rows.map(r=>`<div class="qc-history-row"><div><strong>${esc(r.confirmationReference||r.tradeId)}</strong><span>${esc(r.commodity||'')}</span></div><div><span>${t('measured')}</span><strong>${fmtKg(r.measuredWeightKg)}</strong></div><div><span>${t('variance')}</span><strong>${Number(r.weightVariancePct)>=0?'+':''}${Number(r.weightVariancePct).toFixed(2)}%</strong></div><div><span>${t('status')}</span><strong>${r.accepted?t('ready'):t('disputed')}</strong></div></div>`).join('');
  }

  function init(){
    const css=document.createElement('link');css.rel='stylesheet';css.href='backend/qc-workflow.css';document.head.appendChild(css);injectView();
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{localize();refresh();},0));
    window.addEventListener('agro-auth-changed',()=>setTimeout(refresh,0));
  }

  window.AgroQCWorkflow={refresh,show:showView,loadLocalRecords:localQcRows};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
