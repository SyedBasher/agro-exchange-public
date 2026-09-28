(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const TRADE_KEY='agro_exchange_trade_confirmations_v1';
  const DISPUTE_KEY='agro_exchange_disputes_v1';
  let candidates=[];
  let disputes=[];
  let activeCandidate=null;
  let activeDispute=null;
  let evidenceFiles=[];

  const copy={
    en:{
      nav:'Disputes',kicker:'DISPUTE RESOLUTION',title:'Disputes & adjustments',sub:'Record disagreements explicitly and change commercial terms only after both seller and buyer accept the same proposal.',
      live:'Live shared workflow',local:'Workflow test · device only',notice:'Original trade terms remain preserved. An accepted adjustment becomes the settlement basis without rewriting the original confirmation.',
      openSection:'Trades eligible for review',openSub:'Open a case when quantity, grade, condition, delivery or payment differs from what was agreed.',cases:'Dispute cases',casesSub:'Open, proposed and resolved cases with a two-party acceptance trail.',
      emptyTrades:'No eligible trades are available.',emptyCases:'No dispute cases yet.',open:'Open dispute',propose:'Propose resolution',accept:'Accept proposal',reject:'Reject proposal',simulate:'Simulate counterparty acceptance',view:'View',
      trade:'Trade',route:'Route',commodity:'Commodity',status:'Status',original:'Original terms',resume:'Resume after resolution',type:'Issue type',summary:'Short summary',details:'Details',evidence:'Evidence photos',evidenceHelp:'Up to 4 JPEG/PNG/WebP images, maximum 5 MB each.',saveDispute:'Open dispute case',
      quantity:'Quantity shortfall',grade:'Grade mismatch',damage:'Damage / condition',rejection:'Delivery rejection',payment:'Payment issue',other:'Other',
      proposal:'Resolution proposal',resolution:'Resolution type',acceptOriginal:'Accept original terms',revise:'Revise quantity / price / grade',partial:'Partial rejection',full:'Full rejection',cancel:'Mutual cancellation',
      proposedQty:'Revised commercial quantity (kg)',proposedPrice:'Revised unit price (Tk/kg)',proposedGrade:'Revised grade code (optional)',rationale:'Reason for proposal',saveProposal:'Send proposal',
      seller:'Seller',buyer:'Buyer',accepted:'Accepted',pending:'Pending',rejected:'Rejected',resolved:'Resolved',caseOpen:'Open',proposalPending:'Proposal pending',cancelled:'Cancelled',
      amount:'Proposed amount due',originalAmount:'Original contract amount',proposalHelp:'The proposer accepts their own terms automatically. The counterparty must independently accept the same proposal.',
      rejectReason:'Reason for rejection',saveReject:'Reject proposal',savedDispute:'Dispute opened',savedProposal:'Resolution proposal saved',savedResponse:'Proposal response saved',
      badFile:'Only JPEG, PNG or WebP images up to 5 MB are allowed.',tooMany:'Select no more than four evidence images.',summaryRequired:'Enter a short summary.',termsRequired:'Quantity and unit price are required for revised terms.',
      activeExists:'This trade already has an active dispute.',simulated:'SIMULATED',commercialBoundary:'No unilateral repricing',close:'Close'
    },
    bn:{
      nav:'বিরোধ',kicker:'বিরোধ নিষ্পত্তি',title:'বিরোধ ও বাণিজ্যিক সমন্বয়',sub:'অমিল স্পষ্টভাবে নথিবদ্ধ করুন এবং বিক্রেতা ও ক্রেতা একই প্রস্তাবে সম্মত হলেই বাণিজ্যিক শর্ত পরিবর্তন করুন।',
      live:'লাইভ শেয়ার্ড ওয়ার্কফ্লো',local:'ওয়ার্কফ্লো পরীক্ষা · শুধু ডিভাইসে',notice:'মূল লেনদেনের শর্ত অপরিবর্তিত থাকে। গৃহীত সমন্বয় মূল নিশ্চিতকরণ মুছে না দিয়ে নিষ্পত্তির ভিত্তি হয়।',
      openSection:'পর্যালোচনার যোগ্য লেনদেন',openSub:'পরিমাণ, গ্রেড, অবস্থা, ডেলিভারি বা পেমেন্টে অমিল হলে কেস খুলুন।',cases:'বিরোধের কেস',casesSub:'দুই পক্ষের সম্মতির রেকর্ডসহ খোলা, প্রস্তাবিত ও নিষ্পত্তিকৃত কেস।',
      emptyTrades:'কোনো যোগ্য লেনদেন নেই।',emptyCases:'এখনো কোনো বিরোধ নেই।',open:'বিরোধ খুলুন',propose:'সমাধান প্রস্তাব করুন',accept:'প্রস্তাব গ্রহণ করুন',reject:'প্রস্তাব প্রত্যাখ্যান করুন',simulate:'অন্য পক্ষের সম্মতি সিমুলেট করুন',view:'দেখুন',
      trade:'লেনদেন',route:'রুট',commodity:'পণ্য',status:'অবস্থা',original:'মূল শর্ত',resume:'সমাধানের পর অবস্থা',type:'সমস্যার ধরন',summary:'সংক্ষিপ্ত বিবরণ',details:'বিস্তারিত',evidence:'প্রমাণের ছবি',evidenceHelp:'সর্বোচ্চ ৪টি JPEG/PNG/WebP ছবি, প্রতিটি সর্বোচ্চ ৫ MB।',saveDispute:'বিরোধের কেস খুলুন',
      quantity:'পরিমাণ কম',grade:'গ্রেড অমিল',damage:'ক্ষতি / অবস্থা',rejection:'ডেলিভারি প্রত্যাখ্যান',payment:'পেমেন্ট সমস্যা',other:'অন্যান্য',
      proposal:'সমাধান প্রস্তাব',resolution:'সমাধানের ধরন',acceptOriginal:'মূল শর্ত গ্রহণ',revise:'পরিমাণ / মূল্য / গ্রেড সংশোধন',partial:'আংশিক প্রত্যাখ্যান',full:'সম্পূর্ণ প্রত্যাখ্যান',cancel:'পারস্পরিক বাতিল',
      proposedQty:'সংশোধিত বাণিজ্যিক পরিমাণ (কেজি)',proposedPrice:'সংশোধিত একক মূল্য (টাকা/কেজি)',proposedGrade:'সংশোধিত গ্রেড কোড (ঐচ্ছিক)',rationale:'প্রস্তাবের কারণ',saveProposal:'প্রস্তাব পাঠান',
      seller:'বিক্রেতা',buyer:'ক্রেতা',accepted:'গৃহীত',pending:'অপেক্ষমাণ',rejected:'প্রত্যাখ্যাত',resolved:'নিষ্পত্তি',caseOpen:'খোলা',proposalPending:'প্রস্তাব অপেক্ষমাণ',cancelled:'বাতিল',
      amount:'প্রস্তাবিত পাওনা',originalAmount:'মূল চুক্তির অঙ্ক',proposalHelp:'প্রস্তাবকারী নিজের শর্তে স্বয়ংক্রিয়ভাবে সম্মত হন। অপর পক্ষকে একই প্রস্তাব স্বাধীনভাবে গ্রহণ করতে হবে।',
      rejectReason:'প্রত্যাখ্যানের কারণ',saveReject:'প্রস্তাব প্রত্যাখ্যান করুন',savedDispute:'বিরোধ খোলা হয়েছে',savedProposal:'সমাধান প্রস্তাব সংরক্ষিত হয়েছে',savedResponse:'প্রস্তাবের উত্তর সংরক্ষিত হয়েছে',
      badFile:'শুধু JPEG, PNG বা WebP ছবি, সর্বোচ্চ ৫ MB, ব্যবহার করা যাবে।',tooMany:'সর্বোচ্চ চারটি প্রমাণের ছবি নির্বাচন করুন।',summaryRequired:'সংক্ষিপ্ত বিবরণ লিখুন।',termsRequired:'সংশোধিত শর্তে পরিমাণ ও একক মূল্য প্রয়োজন।',
      activeExists:'এই লেনদেনে ইতিমধ্যে সক্রিয় বিরোধ আছে।',simulated:'সিমুলেটেড',commercialBoundary:'একতরফা মূল্য পরিবর্তন নয়',close:'বন্ধ করুন'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token());}
  function uid(){return window.crypto?.randomUUID?.()||('local-'+Date.now()+'-'+Math.random().toString(16).slice(2));}
  function read(key){try{return JSON.parse(localStorage.getItem(key)||'[]');}catch{return [];}}
  function write(key,rows){localStorage.setItem(key,JSON.stringify(rows.slice(0,100)));}
  function money(v){return 'Tk '+Number(v||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:2});}
  function kg(v){return Number(v||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:1})+' kg';}
  function statusLabel(s){return ({open:t('caseOpen'),proposal_pending:t('proposalPending'),resolved:t('resolved'),cancelled:t('cancelled'),disputed:t('caseOpen')})[s]||s||'—';}
  function issueLabel(s){return ({quantity_shortfall:t('quantity'),grade_mismatch:t('grade'),damage_condition:t('damage'),delivery_rejection:t('rejection'),payment_issue:t('payment'),other:t('other')})[s]||s;}
  function resolutionLabel(s){return ({accept_original:t('acceptOriginal'),revise_terms:t('revise'),partial_rejection:t('partial'),full_rejection:t('full'),cancel_trade:t('cancel')})[s]||s||'—';}

  async function rpc(name,body={}){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body)});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  function localCandidates(){
    const active=new Set(read(DISPUTE_KEY).filter(d=>['open','proposal_pending'].includes(d.dispute_status)).map(d=>d.trade_id));
    const trades=read(TRADE_KEY).filter(x=>x.tradeId&&!['settled','cancelled'].includes(x.tradeStatus||'delivered'));
    const out=trades.map(x=>({trade_id:x.tradeId,confirmation_reference:x.reference||x.tradeId,commodity_code:String(x.commodity||'Potato').toUpperCase(),commodity_name_en:x.commodity||'Potato',commodity_name_bn:x.commodity==='Rice'?'চাল':x.commodity==='Onion'?'পেঁয়াজ':'আলু',grade_code:x.grade||'A',origin_district:x.origin||'Bogra',destination_district:x.destination||'Dhaka',agreed_quantity_kg:Number(x.quantityKg||5000),agreed_price_bdt_per_kg:Number(x.price||31.5),trade_status:x.tradeStatus||'delivered',active_dispute_id:active.has(x.tradeId)?'local-active':null,is_seller:true,is_buyer:true,source:'local'}));
    if(!out.length)out.push({trade_id:'TR-DEMO-DSP-001',confirmation_reference:'AX-DEMO-DSP-001',commodity_code:'POTATO',commodity_name_en:'Potato',commodity_name_bn:'আলু',grade_code:'A',origin_district:'Bogra',destination_district:'Dhaka',agreed_quantity_kg:5000,agreed_price_bdt_per_kg:31.5,trade_status:'delivered',active_dispute_id:active.has('TR-DEMO-DSP-001')?'local-active':null,is_seller:true,is_buyer:true,source:'demo'});
    return out;
  }
  function localDisputes(){return read(DISPUTE_KEY);}

  function injectView(){
    if(document.getElementById('disputes'))return;
    const main=document.querySelector('main.content');if(!main)return;
    const s=document.createElement('section');s.id='disputes';s.className='view';
    s.innerHTML=`<div class="page-heading"><div><div class="breadcrumb" data-dsp-key="kicker"></div><h1 data-dsp-key="title"></h1><p data-dsp-key="sub"></p></div><div class="heading-actions"><span class="dsp-boundary" data-dsp-key="commercialBoundary"></span><button id="dspRefresh" class="button secondary" type="button">↻</button></div></div><div class="dsp-notice"><strong id="dspMode"></strong><span data-dsp-key="notice"></span></div><section class="card dsp-card"><div class="dsp-card-head"><div><h2 data-dsp-key="openSection"></h2><p data-dsp-key="openSub"></p></div></div><div id="disputeCandidates" class="dsp-list"></div></section><section class="card dsp-card"><div class="dsp-card-head"><div><h2 data-dsp-key="cases"></h2><p data-dsp-key="casesSub"></p></div></div><div id="disputeCases" class="dsp-list"></div></section>`;
    main.appendChild(s);document.getElementById('dspRefresh').addEventListener('click',refresh);wireNav();localize();refresh();
  }

  function wireNav(){
    if(document.querySelector('[data-dispute-nav]'))return;
    const trades=document.querySelector('[data-i18n="nav_trades"]')?.closest('.side-link');if(!trades)return;
    const b=document.createElement('button');b.className='side-link';b.dataset.view='disputes';b.dataset.disputeNav='1';b.innerHTML=`<span class="nav-icon">!</span><span data-dsp-nav>${t('nav')}</span>`;trades.insertAdjacentElement('afterend',b);b.addEventListener('click',showView);
  }
  function showView(){document.querySelectorAll('.view').forEach(v=>v.classList.remove('active-view'));document.getElementById('disputes')?.classList.add('active-view');document.querySelectorAll('.side-link[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view==='disputes'));document.querySelector('.sidebar')?.classList.remove('open');document.getElementById('mobileOverlay')?.classList.remove('show');window.scrollTo({top:0,behavior:'smooth'});refresh();}
  function localize(){document.querySelectorAll('#disputes [data-dsp-key],#dspModal [data-dsp-key]').forEach(el=>el.textContent=t(el.dataset.dspKey));document.querySelectorAll('[data-dsp-nav]').forEach(el=>el.textContent=t('nav'));const m=document.getElementById('dspMode');if(m)m.textContent=liveReady()?t('live'):t('local');}

  async function refresh(){
    localize();
    try{
      if(liveReady()) [candidates,disputes]=await Promise.all([rpc('get_dispute_candidates'),rpc('get_my_disputes')]);
      else {candidates=localCandidates();disputes=localDisputes();}
      renderCandidates();renderDisputes();
    }catch(err){console.error(err);const a=document.getElementById('disputeCandidates');if(a)a.innerHTML=`<div class="dsp-empty">${esc(err.message)}</div>`;}
  }

  function renderCandidates(){
    const el=document.getElementById('disputeCandidates');if(!el)return;const rows=candidates.filter(x=>!x.active_dispute_id);
    if(!rows.length){el.innerHTML=`<div class="dsp-empty">${t('emptyTrades')}</div>`;return;}
    el.innerHTML=rows.map((r,i)=>`<article class="dsp-row"><div class="dsp-main"><span class="dsp-ref">${esc(r.confirmation_reference||r.trade_id)}</span><strong>${esc(lang()==='bn'?(r.commodity_name_bn||r.commodity_name_en):(r.commodity_name_en||r.commodity_code))}</strong><span>${esc(r.origin_district)} → ${esc(r.destination_district)}</span></div><div><span>${t('original')}</span><strong>${kg(r.agreed_quantity_kg)} · ${money(r.agreed_price_bdt_per_kg)}/kg</strong></div><div><span>${t('status')}</span><strong>${esc(r.trade_status)}</strong></div><button class="button secondary dsp-open" data-i="${i}" type="button">${t('open')}</button></article>`).join('');
    el.querySelectorAll('.dsp-open').forEach(b=>b.addEventListener('click',()=>openDispute(rows[Number(b.dataset.i)])));
  }

  function acceptanceChips(d){if(!d.proposal_id)return '';return `<div class="dsp-acceptance"><span class="${d.seller_accepted?'ok':''}">${t('seller')}: ${d.seller_accepted?t('accepted'):t('pending')}</span><span class="${d.buyer_accepted?'ok':''}">${t('buyer')}: ${d.buyer_accepted?t('accepted'):t('pending')}</span></div>`;}
  function disputeActions(d,i){
    if(d.dispute_status==='resolved'||d.dispute_status==='cancelled')return `<button class="button secondary dsp-case-action" data-act="view" data-i="${i}">${t('view')}</button>`;
    if(!d.proposal_id||d.proposal_status==='rejected')return `<button class="button primary dsp-case-action" data-act="propose" data-i="${i}">${t('propose')}</button>`;
    if(d.proposal_status==='pending'){
      const myAccepted=liveReady()?((d.is_seller&&d.seller_accepted)||(d.is_buyer&&d.buyer_accepted)):d.seller_accepted;
      if(!myAccepted)return `<button class="button primary dsp-case-action" data-act="accept" data-i="${i}">${t('accept')}</button><button class="button secondary dsp-case-action" data-act="reject" data-i="${i}">${t('reject')}</button>`;
      if(!liveReady()&&!d.buyer_accepted)return `<button class="button primary dsp-case-action" data-act="simulate" data-i="${i}">${t('simulate')}</button>`;
    }
    return `<button class="button secondary dsp-case-action" data-act="view" data-i="${i}">${t('view')}</button>`;
  }
  function renderDisputes(){
    const el=document.getElementById('disputeCases');if(!el)return;if(!disputes.length){el.innerHTML=`<div class="dsp-empty">${t('emptyCases')}</div>`;return;}
    el.innerHTML=disputes.map((d,i)=>`<article class="dsp-case"><div class="dsp-main"><span class="dsp-ref">${esc(d.confirmation_reference||d.trade_id)}</span><strong>${esc(issueLabel(d.dispute_type))}</strong><span>${esc(d.origin_district||'')} → ${esc(d.destination_district||'')}</span></div><div class="dsp-case-body"><p>${esc(d.dispute_summary||d.summary||'')}</p><div class="dsp-meta"><span>${statusLabel(d.dispute_status)}</span>${d.proposal_id?`<span>${resolutionLabel(d.resolution_type)} · ${money(d.proposed_amount_due_bdt||0)}</span>`:''}</div>${acceptanceChips(d)}</div><div class="dsp-actions">${disputeActions(d,i)}</div></article>`).join('');
    el.querySelectorAll('.dsp-case-action').forEach(b=>b.addEventListener('click',()=>handleCase(disputes[Number(b.dataset.i)],b.dataset.act)));
  }

  function injectModal(){if(document.getElementById('dspModal'))return;const m=document.createElement('div');m.id='dspModal';m.className='dsp-modal';m.innerHTML=`<div class="dsp-backdrop" data-dsp-close></div><section class="dsp-sheet"><button class="dsp-close" data-dsp-close type="button">×</button><div class="dsp-brand">Agro-Exchange</div><div id="dspModalBody"></div></section>`;document.body.appendChild(m);m.querySelectorAll('[data-dsp-close]').forEach(x=>x.addEventListener('click',closeModal));}
  function closeModal(){document.getElementById('dspModal')?.classList.remove('open');}
  function summaryBlock(r){return `<div class="dsp-summary"><div><span>${t('trade')}</span><strong>${esc(r.confirmation_reference||r.trade_id)}</strong></div><div><span>${t('route')}</span><strong>${esc(r.origin_district||'')} → ${esc(r.destination_district||'')}</strong></div><div><span>${t('originalAmount')}</span><strong>${money(Number(r.agreed_quantity_kg||0)*Number(r.agreed_price_bdt_per_kg||0))}</strong></div></div>`;}

  function openDispute(r){injectModal();activeCandidate=r;evidenceFiles=[];const body=document.getElementById('dspModalBody');body.innerHTML=`<div class="section-kicker">${t('kicker')}</div><h2>${t('open')}</h2>${summaryBlock(r)}<form id="dspOpenForm" class="dsp-form"><label><span>${t('type')}</span><select name="type"><option value="quantity_shortfall">${t('quantity')}</option><option value="grade_mismatch">${t('grade')}</option><option value="damage_condition">${t('damage')}</option><option value="delivery_rejection">${t('rejection')}</option><option value="payment_issue">${t('payment')}</option><option value="other">${t('other')}</option></select></label><label class="dsp-wide"><span>${t('summary')}</span><input name="summary" maxlength="180" required></label><label class="dsp-wide"><span>${t('details')}</span><textarea name="details" maxlength="1200"></textarea></label><label class="dsp-wide"><span>${t('evidence')}</span><input id="dspEvidence" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" multiple><small>${t('evidenceHelp')}</small></label><div id="dspFiles" class="dsp-files dsp-wide"></div><button class="button primary dsp-wide" type="submit">${t('saveDispute')}</button></form>`;document.getElementById('dspEvidence').addEventListener('change',onFiles);document.getElementById('dspOpenForm').addEventListener('submit',submitDispute);document.getElementById('dspModal').classList.add('open');}
  function onFiles(e){evidenceFiles=Array.from(e.target.files||[]);document.getElementById('dspFiles').innerHTML=evidenceFiles.map(f=>`<span>${esc(f.name)} · ${(f.size/1024/1024).toFixed(1)} MB</span>`).join('');}
  function validateFiles(){if(evidenceFiles.length>4)throw new Error(t('tooMany'));for(const f of evidenceFiles){if(!['image/jpeg','image/png','image/webp'].includes(f.type)||f.size>5242880)throw new Error(t('badFile'));}}
  function safeFile(name){return String(name||'evidence').replace(/[^A-Za-z0-9._-]+/g,'-').slice(-90);}
  async function upload(file,tradeId){const path=tradeId+'/'+uid()+'-'+safeFile(file.name);const encoded=path.split('/').map(encodeURIComponent).join('/');const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/storage/v1/object/dispute-evidence/'+encoded,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':file.type,'x-upsert':'false'},body:file});const text=await r.text();if(!r.ok)throw new Error(text||'Evidence upload failed');return path;}

  async function submitDispute(e){e.preventDefault();const f=e.currentTarget,summary=String(f.elements.summary.value||'').trim();if(summary.length<3){toast?.(t('summaryRequired'));return;}try{validateFiles();const evidence=[];if(liveReady())for(const file of evidenceFiles)evidence.push(await upload(file,activeCandidate.trade_id));else evidence.push(...evidenceFiles.map(file=>({name:file.name,type:file.type,size:file.size,localOnly:true})));
    if(liveReady())await rpc('open_trade_dispute',{p_trade_id:activeCandidate.trade_id,p_dispute_type:f.elements.type.value,p_summary:summary,p_details:String(f.elements.details.value||'')||null,p_evidence_objects:evidence});
    else{const all=read(DISPUTE_KEY);all.unshift({dispute_id:uid(),trade_id:activeCandidate.trade_id,confirmation_reference:activeCandidate.confirmation_reference,dispute_type:f.elements.type.value,dispute_summary:summary,dispute_details:String(f.elements.details.value||''),dispute_status:'open',resume_trade_status:activeCandidate.trade_status,evidence_objects:evidence,opened_at:new Date().toISOString(),commodity_code:activeCandidate.commodity_code,commodity_name_en:activeCandidate.commodity_name_en,commodity_name_bn:activeCandidate.commodity_name_bn,grade_code:activeCandidate.grade_code,origin_district:activeCandidate.origin_district,destination_district:activeCandidate.destination_district,agreed_quantity_kg:activeCandidate.agreed_quantity_kg,agreed_price_bdt_per_kg:activeCandidate.agreed_price_bdt_per_kg,is_seller:true,is_buyer:true});write(DISPUTE_KEY,all);}
    closeModal();toast?.(t('savedDispute'));await refresh();
  }catch(err){toast?.(err.message||'Could not open dispute.');}}

  function handleCase(d,act){activeDispute=d;if(act==='propose')return openProposal(d);if(act==='accept'||act==='simulate')return respond(d,true,act==='simulate');if(act==='reject')return openReject(d);return openView(d);}
  function openProposal(d){injectModal();const body=document.getElementById('dspModalBody');body.innerHTML=`<div class="section-kicker">${t('proposal')}</div><h2>${t('propose')}</h2>${summaryBlock(d)}<p class="dsp-help">${t('proposalHelp')}</p><form id="dspProposalForm" class="dsp-form"><label><span>${t('resolution')}</span><select name="resolution" id="dspResolution"><option value="accept_original">${t('acceptOriginal')}</option><option value="revise_terms">${t('revise')}</option><option value="partial_rejection">${t('partial')}</option><option value="full_rejection">${t('full')}</option><option value="cancel_trade">${t('cancel')}</option></select></label><label data-term-field><span>${t('proposedQty')}</span><input name="qty" type="number" min="0.1" step="0.1" inputmode="decimal" value="${Number(d.agreed_quantity_kg||0)}"></label><label data-term-field><span>${t('proposedPrice')}</span><input name="price" type="number" min="0" step="0.01" inputmode="decimal" value="${Number(d.agreed_price_bdt_per_kg||0)}"></label><label data-term-field><span>${t('proposedGrade')}</span><input name="grade" maxlength="20" value="${esc(d.grade_code||'')}"></label><label class="dsp-wide"><span>${t('rationale')}</span><textarea name="rationale" maxlength="900"></textarea></label><button class="button primary dsp-wide" type="submit">${t('saveProposal')}</button></form>`;const sel=document.getElementById('dspResolution');const toggle=()=>document.querySelectorAll('#dspProposalForm [data-term-field]').forEach(x=>x.classList.toggle('dsp-hidden',!['revise_terms','partial_rejection'].includes(sel.value)));sel.addEventListener('change',toggle);toggle();document.getElementById('dspProposalForm').addEventListener('submit',submitProposal);document.getElementById('dspModal').classList.add('open');}

  async function submitProposal(e){e.preventDefault();const f=e.currentTarget,res=f.elements.resolution.value,needs=['revise_terms','partial_rejection'].includes(res),qty=needs?Number(f.elements.qty.value||0):null,price=needs?Number(f.elements.price.value):null;if(needs&&(!Number.isFinite(qty)||qty<=0||!Number.isFinite(price)||price<0)){toast?.(t('termsRequired'));return;}try{
    if(liveReady())await rpc('propose_trade_adjustment',{p_dispute_id:activeDispute.dispute_id,p_resolution_type:res,p_quantity_kg:qty,p_unit_price_bdt_per_kg:price,p_grade_code:needs?(String(f.elements.grade.value||'')||null):null,p_rationale:String(f.elements.rationale.value||'')||null});
    else{const all=read(DISPUTE_KEY),d=all.find(x=>x.dispute_id===activeDispute.dispute_id);if(d){d.proposal_id=uid();d.resolution_type=res;d.proposed_quantity_kg=needs?qty:Number(d.agreed_quantity_kg);d.proposed_unit_price_bdt_per_kg=needs?price:Number(d.agreed_price_bdt_per_kg);d.proposed_grade_code=needs?String(f.elements.grade.value||''):d.grade_code;d.proposed_amount_due_bdt=['full_rejection','cancel_trade'].includes(res)?0:Number(d.proposed_quantity_kg)*Number(d.proposed_unit_price_bdt_per_kg);d.proposal_rationale=String(f.elements.rationale.value||'');d.proposal_status='pending';d.seller_accepted=true;d.buyer_accepted=false;d.dispute_status='proposal_pending';write(DISPUTE_KEY,all);}}
    closeModal();toast?.(t('savedProposal'));await refresh();
  }catch(err){toast?.(err.message||'Could not save proposal.');}}

  async function respond(d,accept,simulate){try{if(liveReady())await rpc('respond_trade_adjustment',{p_proposal_id:d.proposal_id,p_accept:accept,p_note:null});else{const all=read(DISPUTE_KEY),x=all.find(y=>y.dispute_id===d.dispute_id);if(x){if(simulate||x.seller_accepted)x.buyer_accepted=true;else x.seller_accepted=true;if(x.seller_accepted&&x.buyer_accepted){x.proposal_status='accepted';x.dispute_status='resolved';x.trade_status=['full_rejection','cancel_trade'].includes(x.resolution_type)?'cancelled':x.resume_trade_status;}write(DISPUTE_KEY,all);}}toast?.(t('savedResponse'));await refresh();}catch(err){toast?.(err.message||'Could not save response.');}}
  function openReject(d){injectModal();document.getElementById('dspModalBody').innerHTML=`<div class="section-kicker">${t('proposal')}</div><h2>${t('reject')}</h2>${summaryBlock(d)}<form id="dspRejectForm" class="dsp-form"><label class="dsp-wide"><span>${t('rejectReason')}</span><textarea name="reason" required></textarea></label><button class="button secondary dsp-wide" type="submit">${t('saveReject')}</button></form>`;document.getElementById('dspRejectForm').addEventListener('submit',async e=>{e.preventDefault();try{if(liveReady())await rpc('respond_trade_adjustment',{p_proposal_id:d.proposal_id,p_accept:false,p_note:String(e.currentTarget.elements.reason.value||'')});else{const all=read(DISPUTE_KEY),x=all.find(y=>y.dispute_id===d.dispute_id);if(x){x.proposal_status='rejected';x.dispute_status='open';write(DISPUTE_KEY,all);}}closeModal();toast?.(t('savedResponse'));await refresh();}catch(err){toast?.(err.message||'Could not reject proposal.');}});document.getElementById('dspModal').classList.add('open');}
  function openView(d){injectModal();document.getElementById('dspModalBody').innerHTML=`<div class="section-kicker">${t('type')}</div><h2>${esc(issueLabel(d.dispute_type))}</h2>${summaryBlock(d)}<div class="dsp-detail"><p><strong>${t('summary')}:</strong> ${esc(d.dispute_summary||'')}</p><p><strong>${t('status')}:</strong> ${statusLabel(d.dispute_status)}</p><p><strong>${t('resume')}:</strong> ${esc(d.resume_trade_status||'—')}</p>${d.proposal_id?`<p><strong>${t('resolution')}:</strong> ${resolutionLabel(d.resolution_type)}</p><p><strong>${t('amount')}:</strong> ${money(d.proposed_amount_due_bdt||0)}</p>${acceptanceChips(d)}`:''}</div>`;document.getElementById('dspModal').classList.add('open');}

  function init(){const css=document.createElement('link');css.rel='stylesheet';css.href='backend/dispute-workflow.css';document.head.appendChild(css);injectView();document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(()=>{localize();renderCandidates();renderDisputes();},0));window.addEventListener('agro-auth-changed',()=>setTimeout(refresh,0));}
  window.AgroDisputes={refresh,show:showView};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
