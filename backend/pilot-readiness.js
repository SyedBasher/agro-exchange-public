(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  let state={notifications:[],preferences:null,reliability:null,pilot:null,exceptions:[],qc:[]};

  const copy={
    en:{
      nav:'Pilot readiness',kicker:'PILOT READINESS',title:'Reliability, alerts & QC economics',
      sub:'Use transparent operating evidence to learn what works before scaling. Performance history is descriptive and never collapsed into an opaque score.',
      modeLive:'Live pilot-readiness data',modeDemo:'Pilot-readiness demo · simulated',refresh:'Refresh',unavailable:'Live data unavailable — refresh when the database is reachable.',
      history:'Performance history',historySub:'Show sample size and observable outcomes. A small history is labelled limited rather than converted into a misleading rating.',
      noScore:'No star rating / no black-box score',sample:'Evidence level',limited:'Limited (<3 trades)',developing:'Developing (3–9 trades)',established:'Established (10+ trades)',
      trades:'Trades',settled:'Settled',disputes:'Trades with disputes',cancelled:'Cancelled',qcChecks:'QC checks',qcReject:'QC rejection rate',onTime:'On-time delivery',receiptAccept:'Receipt acceptance',receiptTime:'Delivery → receipt',settleTime:'Receipt → settlement',hours:'hours',
      qcTitle:'QC cost & learning',qcSub:'Measure direct inspection cost, time and outcomes. QC-required versus QC-bypassed comparisons are descriptive because trades are not randomly assigned to QC.',
      avgQcCost:'Avg recorded QC cost',qcCostShare:'Avg QC cost / trade value',qcCycle:'Avg QC cycle',qcRejection:'QC rejection rate',qcRequired:'QC-required trades',qcBypassed:'QC-bypassed trades',qcDispute:'QC-required dispute rate',bypassDispute:'QC-bypassed dispute rate',
      telemetry:'QC telemetry queue',telemetrySub:'Record actual direct cost and inspection intensity so the pilot can later judge when QC is worth paying for.',level:'Inspection level',basic:'Basic',independent:'Independent',enhanced:'Enhanced',cost:'Direct cost (Tk)',reason:'Reason',save:'Save',complete:'Recorded',missing:'Missing telemetry',noQc:'No QC records yet.',
      exceptions:'Exception escalation',exceptionsSub:'Overdue trades receive a suggested escalation level based on how far they exceed the current pilot threshold.',trade:'Trade',status:'Status',overdue:'Overdue',suggested:'Suggested level',current:'Current escalation',escalate:'Escalate',resolve:'Resolve',none:'None',noExceptions:'No overdue trades at present.',
      inbox:'In-app notifications',inboxSub:'In-app transactional alerts are active. SMS and push preferences can be stored, but external delivery is not connected yet.',markAll:'Mark all read',unread:'Unread',read:'Read',noNotifications:'No notifications yet.',providerPending:'Preference only — external provider not connected',sms:'SMS when available',push:'Push when available',prefs:'Future channel preferences',savePrefs:'Save preferences',
      totalTrades:'Total trades',activeDisputes:'Active disputes',openEscalations:'Open escalations',unreadAlerts:'Unread alerts',qcCostCoverage:'QC cost records',
      pilotCaution:'Pilot interpretation',pilotCautionText:'Do not read a lower dispute rate among QC trades as the causal effect of QC. Higher-risk trades may be selected into QC. We need enough observations and a credible comparison before making that claim.',
      accessNote:'Live aggregate pilot metrics and escalation controls require an approved admin account. Personal notifications and performance history work for signed-in participants.',
      saved:'Saved',simulated:'SIMULATED',level1:'Level 1',level2:'Level 2',level3:'Level 3'
    },
    bn:{
      nav:'পাইলট প্রস্তুতি',kicker:'পাইলট প্রস্তুতি',title:'নির্ভরযোগ্যতা, সতর্কতা ও QC ব্যয়',
      sub:'বড় পরিসরে যাওয়ার আগে স্বচ্ছ অপারেশন তথ্য দিয়ে কী কাজ করছে তা শিখুন। পারফরম্যান্স ইতিহাসকে কোনো অস্বচ্ছ স্কোরে নামিয়ে আনা হবে না।',
      modeLive:'লাইভ পাইলট-প্রস্তুতি তথ্য',modeDemo:'পাইলট-প্রস্তুতি ডেমো · সিমুলেটেড',refresh:'রিফ্রেশ',unavailable:'লাইভ তথ্য পাওয়া যাচ্ছে না — ডেটাবেজ সংযোগ ফিরলে রিফ্রেশ করুন।',
      history:'পারফরম্যান্স ইতিহাস',historySub:'নমুনার আকার ও দেখা ফলাফল দেখান। অল্প ইতিহাসকে বিভ্রান্তিকর রেটিং না দিয়ে সীমিত বলা হবে।',
      noScore:'স্টার রেটিং নেই / ব্ল্যাক-বক্স স্কোর নেই',sample:'তথ্যের স্তর',limited:'সীমিত (<৩ লেনদেন)',developing:'উন্নয়নশীল (৩–৯ লেনদেন)',established:'প্রতিষ্ঠিত (১০+ লেনদেন)',
      trades:'লেনদেন',settled:'নিষ্পত্তি',disputes:'বিরোধসহ লেনদেন',cancelled:'বাতিল',qcChecks:'QC পরীক্ষা',qcReject:'QC প্রত্যাখ্যান হার',onTime:'সময়ে ডেলিভারি',receiptAccept:'রিসিপ্ট গ্রহণ',receiptTime:'ডেলিভারি → রিসিপ্ট',settleTime:'রিসিপ্ট → নিষ্পত্তি',hours:'ঘণ্টা',
      qcTitle:'QC খরচ ও শেখা',qcSub:'সরাসরি পরিদর্শন খরচ, সময় ও ফলাফল মাপুন। QC-প্রয়োজন ও QC-বাইপাস তুলনা বর্ণনামূলক, কারণ লেনদেনগুলো এলোমেলোভাবে QC-তে যায় না।',
      avgQcCost:'গড় নথিভুক্ত QC খরচ',qcCostShare:'গড় QC খরচ / লেনদেন মূল্য',qcCycle:'গড় QC সময়',qcRejection:'QC প্রত্যাখ্যান হার',qcRequired:'QC-প্রয়োজন লেনদেন',qcBypassed:'QC-বাইপাস লেনদেন',qcDispute:'QC-প্রয়োজন বিরোধ হার',bypassDispute:'QC-বাইপাস বিরোধ হার',
      telemetry:'QC টেলিমেট্রি তালিকা',telemetrySub:'বাস্তব সরাসরি খরচ ও পরিদর্শনের মাত্রা নথিভুক্ত করুন, যাতে পাইলটে বোঝা যায় কখন QC খরচ করা যুক্তিযুক্ত।',level:'পরিদর্শন স্তর',basic:'বেসিক',independent:'স্বাধীন',enhanced:'বর্ধিত',cost:'সরাসরি খরচ (টাকা)',reason:'কারণ',save:'সংরক্ষণ',complete:'নথিভুক্ত',missing:'তথ্য অসম্পূর্ণ',noQc:'এখনো QC রেকর্ড নেই।',
      exceptions:'ব্যতিক্রম এসকেলেশন',exceptionsSub:'পাইলট সীমার তুলনায় কত বেশি সময় আটকে আছে তার ভিত্তিতে ওভারডিউ লেনদেনের প্রস্তাবিত এসকেলেশন স্তর দেখানো হয়।',trade:'লেনদেন',status:'অবস্থা',overdue:'ওভারডিউ',suggested:'প্রস্তাবিত স্তর',current:'বর্তমান এসকেলেশন',escalate:'এসকেলেট',resolve:'সমাধান',none:'নেই',noExceptions:'বর্তমানে কোনো ওভারডিউ লেনদেন নেই।',
      inbox:'ইন-অ্যাপ নোটিফিকেশন',inboxSub:'ইন-অ্যাপ লেনদেন সতর্কতা সক্রিয়। SMS ও push পছন্দ সংরক্ষণ করা যাবে, তবে বাহ্যিক ডেলিভারি এখনো সংযুক্ত নয়।',markAll:'সব পড়া হয়েছে',unread:'অপঠিত',read:'পড়া',noNotifications:'এখনো কোনো নোটিফিকেশন নেই।',providerPending:'শুধু পছন্দ সংরক্ষণ — বাহ্যিক প্রোভাইডার সংযুক্ত নয়',sms:'উপলভ্য হলে SMS',push:'উপলভ্য হলে Push',prefs:'ভবিষ্যৎ চ্যানেল পছন্দ',savePrefs:'পছন্দ সংরক্ষণ',
      totalTrades:'মোট লেনদেন',activeDisputes:'সক্রিয় বিরোধ',openEscalations:'খোলা এসকেলেশন',unreadAlerts:'অপঠিত সতর্কতা',qcCostCoverage:'QC খরচ রেকর্ড',
      pilotCaution:'পাইলট ব্যাখ্যা',pilotCautionText:'QC-সহ লেনদেনে কম বিরোধ দেখা গেলে সেটিকে QC-এর কারণগত প্রভাব বলা যাবে না। বেশি ঝুঁকির লেনদেনই QC-তে যেতে পারে। যথেষ্ট পর্যবেক্ষণ ও বিশ্বাসযোগ্য তুলনা দরকার।',
      accessNote:'লাইভ সামগ্রিক পাইলট মেট্রিক ও এসকেলেশন নিয়ন্ত্রণের জন্য অনুমোদিত অ্যাডমিন দরকার। সাইন-ইন করা অংশগ্রহণকারীরা ব্যক্তিগত নোটিফিকেশন ও পারফরম্যান্স ইতিহাস দেখতে পারবেন।',
      saved:'সংরক্ষিত',simulated:'সিমুলেটেড',level1:'লেভেল ১',level2:'লেভেল ২',level3:'লেভেল ৩'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token());}
  function isAdmin(){return liveReady()&&profile()?.role==='admin';}
  function canQc(){return liveReady()&&['qc_operator','admin'].includes(profile()?.role);}
  function n(v,d=0){const x=Number(v);return Number.isFinite(x)?x:d;}
  function pct(v){return v===null||v===undefined?'—':n(v).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:1})+'%';}
  function money(v){return v===null||v===undefined?'—':'Tk '+n(v).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:0});}
  function num(v){return n(v).toLocaleString(lang()==='bn'?'bn-BD':'en-US',{maximumFractionDigits:1});}
  function bandLabel(v){return t(v||'limited');}

  async function rpc(name,body={}){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body)});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  function demo(){
    return {
      reliability:{entity_type:'seller',metrics:{display_name:'Sample seller',total_trades:7,settled_trades:5,disputed_trades:1,cancelled_trades:0,dispute_trade_rate_pct:14.3,qc_checks:4,qc_rejections:0,qc_rejection_rate_pct:0,delivered_shipments:6,on_time_deliveries:5,on_time_delivery_rate_pct:83.3,avg_delivery_delay_hours:1.7,sample_band:'developing'}},
      pilot:{total_trades:18,settled_trades:11,active_disputes:2,open_escalations:1,unread_in_app_notifications:6,qc_records:10,qc_cost_recorded:7,avg_qc_direct_cost_bdt:620,avg_qc_cost_pct_trade_value:0.42,avg_qc_cycle_hours:3.6,qc_rejection_rate_pct:10,qc_required_trade_count:11,qc_bypassed_trade_count:7,qc_required_dispute_rate_pct:18.2,qc_bypassed_dispute_rate_pct:14.3},
      exceptions:[{trade_id:'TR-DEMO-501',confirmation_reference:'AX-DEMO-501',commodity_code:'POTATO',trade_status:'awaiting_qc',overdue_hours:9.4,suggested_escalation_level:1,open_escalation_id:null,open_escalation_level:null},{trade_id:'TR-DEMO-502',confirmation_reference:'AX-DEMO-502',commodity_code:'ONION',trade_status:'ready_for_dispatch',overdue_hours:27.2,suggested_escalation_level:2,open_escalation_id:'ESC-DEMO',open_escalation_level:2}],
      qc:[{qc_record_id:'QC-DEMO-1',trade_id:'TR-DEMO-QC-1',confirmation_reference:'AX-DEMO-QC-1',commodity_code:'POTATO',agreed_value_bdt:157500,accepted:true,recorded_at:new Date().toISOString(),inspection_level:null,direct_cost_bdt:null,inspection_reason:null,qc_cycle_hours:2.4,telemetry_complete:false},{qc_record_id:'QC-DEMO-2',trade_id:'TR-DEMO-QC-2',confirmation_reference:'AX-DEMO-QC-2',commodity_code:'ONION',agreed_value_bdt:220000,accepted:true,recorded_at:new Date().toISOString(),inspection_level:'independent',direct_cost_bdt:850,inspection_reason:'First trade with counterparty',qc_cycle_hours:4.1,telemetry_complete:true}],
      notifications:[{notification_id:'N-DEMO-1',event_type:'trade_status_changed',priority:'normal',payload:{status:'ready_for_dispatch'},created_at:new Date(Date.now()-1800000).toISOString(),read_at:null},{notification_id:'N-DEMO-2',event_type:'operations_escalation',priority:'high',payload:{level:2,reason:'Dispatch overdue'},created_at:new Date(Date.now()-5400000).toISOString(),read_at:null},{notification_id:'N-DEMO-3',event_type:'trade_status_changed',priority:'normal',payload:{status:'delivered'},created_at:new Date(Date.now()-86400000).toISOString(),read_at:new Date().toISOString()}],
      preferences:{sms_opt_in:false,push_opt_in:false,quiet_hours_start:null,quiet_hours_end:null}
    };
  }

  function inject(){
    if(document.getElementById('pilotReadiness'))return;
    const main=document.querySelector('main.content');if(!main)return;
    const v=document.createElement('section');v.id='pilotReadiness';v.className='view';
    v.innerHTML=`<div class="page-heading"><div><div class="breadcrumb" data-pr-key="kicker"></div><h1 data-pr-key="title"></h1><p data-pr-key="sub"></p></div><div class="heading-actions"><button id="prRefresh" class="button secondary" type="button" data-pr-key="refresh"></button></div></div>
      <div class="pr-mode"><strong id="prMode"></strong><span id="prAccess"></span></div>
      <div id="prMetrics" class="pr-metrics"></div>
      <div class="pr-grid">
        <section class="card pr-wide"><div class="card-head"><div><h2 data-pr-key="history"></h2><p data-pr-key="historySub"></p></div><span class="pr-no-score" data-pr-key="noScore"></span></div><div id="prReliability"></div></section>
        <section class="card pr-wide"><div class="card-head"><div><h2 data-pr-key="qcTitle"></h2><p data-pr-key="qcSub"></p></div></div><div id="prQcMetrics" class="pr-mini-metrics"></div><div class="pr-caution"><strong data-pr-key="pilotCaution"></strong><p data-pr-key="pilotCautionText"></p></div></section>
        <section class="card pr-wide"><div class="card-head"><div><h2 data-pr-key="telemetry"></h2><p data-pr-key="telemetrySub"></p></div></div><div id="prQcQueue"></div></section>
        <section class="card pr-wide"><div class="card-head"><div><h2 data-pr-key="exceptions"></h2><p data-pr-key="exceptionsSub"></p></div></div><div id="prExceptions"></div></section>
        <section id="prInboxCard" class="card pr-wide"><div class="card-head"><div><h2 data-pr-key="inbox"></h2><p data-pr-key="inboxSub"></p></div><button id="prMarkAll" class="button secondary" type="button" data-pr-key="markAll"></button></div><div id="prNotifications"></div><form id="prPrefs" class="pr-prefs"><strong data-pr-key="prefs"></strong><label><input name="sms" type="checkbox"><span data-pr-key="sms"></span></label><label><input name="push" type="checkbox"><span data-pr-key="push"></span></label><small data-pr-key="providerPending"></small><button class="button secondary" type="submit" data-pr-key="savePrefs"></button></form></section>
      </div>`;
    main.appendChild(v);
    const nav=document.querySelector('.secondary-nav');if(nav&&!document.querySelector('[data-view="pilotReadiness"]')){const b=document.createElement('button');b.className='side-link';b.dataset.view='pilotReadiness';b.innerHTML='<span class="nav-icon">◉</span><span data-pr-nav></span>';nav.appendChild(b);b.addEventListener('click',show);}
    injectBell();document.getElementById('prRefresh').addEventListener('click',refresh);document.getElementById('prMarkAll').addEventListener('click',markAll);document.getElementById('prPrefs').addEventListener('submit',savePrefs);localize();refresh();
  }

  function injectBell(){
    if(document.getElementById('prBell'))return;
    const b=document.createElement('button');b.id='prBell';b.className='pr-bell';b.type='button';b.setAttribute('aria-label','Notifications');b.innerHTML='<span>🔔</span><b id="prBellCount">0</b>';b.addEventListener('click',()=>{show();setTimeout(()=>document.getElementById('prInboxCard')?.scrollIntoView({behavior:'smooth',block:'start'}),80);});document.body.appendChild(b);
  }

  function show(){document.querySelectorAll('.view').forEach(x=>x.classList.remove('active-view'));document.getElementById('pilotReadiness')?.classList.add('active-view');document.querySelectorAll('.side-link[data-view]').forEach(x=>x.classList.toggle('active',x.dataset.view==='pilotReadiness'));document.querySelector('.sidebar')?.classList.remove('open');document.getElementById('mobileOverlay')?.classList.remove('show');window.scrollTo({top:0,behavior:'smooth'});refresh();}

  function localize(){document.querySelectorAll('#pilotReadiness [data-pr-key]').forEach(x=>x.textContent=t(x.dataset.prKey));document.querySelectorAll('[data-pr-nav]').forEach(x=>x.textContent=t('nav'));const m=document.getElementById('prMode');if(m)m.textContent=liveReady()?t('modeLive'):t('modeDemo');const a=document.getElementById('prAccess');if(a)a.textContent=liveReady()&&!isAdmin()?t('accessNote'):'';}

  async function refresh(){
    localize();
    const d=demo();
    if(!liveReady()){state=d;render();return;}
    try{
      const [notifications,preferences,reliability]=await Promise.all([rpc('get_my_notifications',{p_limit:80}),rpc('get_my_notification_preferences'),rpc('get_my_reliability_snapshot')]);
      state.notifications=notifications||[];state.preferences=Array.isArray(preferences)?preferences[0]:preferences;state.reliability=reliability||null;
      if(isAdmin()){
        const [pilot,exceptions,qc]=await Promise.all([rpc('get_admin_pilot_readiness'),rpc('get_admin_exception_queue_v1_5'),rpc('get_qc_telemetry_queue')]);
        state.pilot=pilot||{};state.exceptions=exceptions||[];state.qc=qc||[];
      }else if(canQc()){
        state.pilot=null;state.exceptions=[];state.qc=await rpc('get_qc_telemetry_queue');
      }else{state.pilot=null;state.exceptions=[];state.qc=[];}
      render();
    }catch(err){state={reliability:null,pilot:null,exceptions:[],qc:[],notifications:[],preferences:null,loadError:true};render();if(typeof toast==='function')toast(t('unavailable'));}
  }

  function metric(label,value,format='num'){let v=value;if(format==='money')v=money(value);else if(format==='pct')v=pct(value);else v=num(value);return `<article><span>${label}</span><strong>${v}</strong></article>`;}

  function render(){renderMetrics();renderReliability();renderQc();renderExceptions();renderNotifications();renderPrefs();}

  function renderMetrics(){const d=state.pilot||{};const unread=(state.notifications||[]).filter(x=>!x.read_at).length;const items=state.pilot?[metric(t('totalTrades'),d.total_trades),metric(t('settled'),d.settled_trades),metric(t('activeDisputes'),d.active_disputes),metric(t('openEscalations'),d.open_escalations),metric(t('unreadAlerts'),unread),metric(t('qcCostCoverage'),d.qc_cost_recorded)]:[metric(t('unreadAlerts'),unread),metric(t('trades'),state.reliability?.metrics?.total_trades||0),metric(t('settled'),state.reliability?.metrics?.settled_trades||0)];document.getElementById('prMetrics').innerHTML=items.join('');document.getElementById('prBellCount').textContent=String(unread);document.getElementById('prBell').classList.toggle('has-unread',unread>0);}

  function renderReliability(){const m=state.reliability?.metrics||{};const target=document.getElementById('prReliability');if(!Object.keys(m).length){target.innerHTML=`<div class="pr-empty">${t('historySub')}</div>`;return;}const isBuyer=state.reliability?.entity_type==='buyer';let cards=[metric(t('trades'),m.total_trades),metric(t('settled'),m.settled_trades),metric(t('disputes'),m.disputed_trades),metric(t('cancelled'),m.cancelled_trades)];if(isBuyer){cards.push(metric(t('receiptAccept'),m.receipt_acceptance_rate_pct,'pct'),metric(t('receiptTime'),m.avg_receipt_confirmation_hours),metric(t('settleTime'),m.avg_receipt_to_settlement_hours));}else{cards.push(metric(t('qcChecks'),m.qc_checks),metric(t('qcReject'),m.qc_rejection_rate_pct,'pct'),metric(t('onTime'),m.on_time_delivery_rate_pct,'pct'));}target.innerHTML=`<div class="pr-entity"><div><span>${isBuyer?'Buyer / ক্রেতা':'Seller / বিক্রেতা'}</span><strong>${esc(m.display_name||'—')}</strong></div><div><span>${t('sample')}</span><strong>${bandLabel(m.sample_band)}</strong></div></div><div class="pr-mini-metrics">${cards.join('')}</div>`;}

  function renderQc(){const d=state.pilot;if(!d){document.getElementById('prQcMetrics').innerHTML=`<div class="pr-empty">${t('unavailable')}</div>`;const qt=document.getElementById('prQcQueue');if(qt)qt.innerHTML=`<div class="pr-empty">${t('noQc')}</div>`;return;}document.getElementById('prQcMetrics').innerHTML=[metric(t('avgQcCost'),d.avg_qc_direct_cost_bdt,'money'),metric(t('qcCostShare'),d.avg_qc_cost_pct_trade_value,'pct'),metric(t('qcCycle'),d.avg_qc_cycle_hours),metric(t('qcRejection'),d.qc_rejection_rate_pct,'pct'),metric(t('qcRequired'),d.qc_required_trade_count),metric(t('qcBypassed'),d.qc_bypassed_trade_count),metric(t('qcDispute'),d.qc_required_dispute_rate_pct,'pct'),metric(t('bypassDispute'),d.qc_bypassed_dispute_rate_pct,'pct')].join('');const q=state.qc||[];const target=document.getElementById('prQcQueue');if(!q.length){target.innerHTML=`<div class="pr-empty">${t('noQc')}</div>`;return;}target.innerHTML=`<div class="pr-qc-list">${q.map((r,i)=>`<form class="pr-qc-row" data-i="${i}"><div><strong>${esc(r.confirmation_reference||r.trade_id)}</strong><small>${esc(r.commodity_code||'')} · ${money(r.agreed_value_bdt)} · ${num(r.qc_cycle_hours)} ${t('hours')}</small></div><label><span>${t('level')}</span><select name="level"><option value="basic" ${r.inspection_level==='basic'?'selected':''}>${t('basic')}</option><option value="independent" ${r.inspection_level==='independent'?'selected':''}>${t('independent')}</option><option value="enhanced" ${r.inspection_level==='enhanced'?'selected':''}>${t('enhanced')}</option></select></label><label><span>${t('cost')}</span><input name="cost" type="number" min="0" step="1" value="${r.direct_cost_bdt??''}"></label><label class="pr-qc-reason"><span>${t('reason')}</span><input name="reason" type="text" maxlength="240" value="${esc(r.inspection_reason||'')}"></label><div class="pr-qc-action"><span class="pr-status ${r.telemetry_complete?'done':'missing'}">${r.telemetry_complete?t('complete'):t('missing')}</span><button class="button secondary" type="submit">${t('save')}</button></div></form>`).join('')}</div>`;target.querySelectorAll('.pr-qc-row').forEach(f=>f.addEventListener('submit',saveQcTelemetry));}

  async function saveQcTelemetry(e){e.preventDefault();const i=Number(e.currentTarget.dataset.i),r=state.qc[i],level=e.currentTarget.elements.level.value,cost=Number(e.currentTarget.elements.cost.value),reason=String(e.currentTarget.elements.reason.value||'').trim();if(!r||!Number.isFinite(cost)||cost<0)return;try{if(canQc())await rpc('record_qc_telemetry',{p_qc_record_id:r.qc_record_id,p_inspection_level:level,p_direct_cost_bdt:cost,p_inspection_reason:reason||null});else{r.inspection_level=level;r.direct_cost_bdt=cost;r.inspection_reason=reason;r.telemetry_complete=true;}if(typeof toast==='function')toast(t('saved'));await refresh();}catch(err){if(typeof toast==='function')toast(err.message||'Could not save QC telemetry.');}}

  function levelLabel(x){return t('level'+String(x||1));}
  function renderExceptions(){const rows=state.exceptions||[];const target=document.getElementById('prExceptions');if(!rows.length){target.innerHTML=`<div class="pr-empty">${t('noExceptions')}</div>`;return;}target.innerHTML=`<div class="pr-ex-list">${rows.map((r,i)=>`<article><div><strong>${esc(r.confirmation_reference||r.trade_id)}</strong><small>${esc(r.commodity_code||'')} · ${esc(r.trade_status)} · ${num(r.overdue_hours)} ${t('hours')} ${t('overdue')}</small></div><div><span>${t('suggested')}: <b>${levelLabel(r.suggested_escalation_level)}</b></span><span>${t('current')}: <b>${r.open_escalation_id?levelLabel(r.open_escalation_level):t('none')}</b></span></div><button class="button secondary pr-escalate" data-i="${i}" type="button">${r.open_escalation_id?t('resolve'):t('escalate')}</button></article>`).join('')}</div>`;target.querySelectorAll('.pr-escalate').forEach(b=>b.addEventListener('click',()=>toggleEscalation(Number(b.dataset.i))));}

  async function toggleEscalation(i){const r=state.exceptions[i];if(!r)return;try{if(isAdmin()){if(r.open_escalation_id)await rpc('admin_resolve_trade_escalation',{p_escalation_id:r.open_escalation_id,p_resolution_note:'Reviewed through pilot-readiness console'});else await rpc('admin_raise_trade_escalation',{p_trade_id:r.trade_id,p_level:r.suggested_escalation_level,p_reason:'Trade exceeded the current pilot operating threshold'});}else{if(r.open_escalation_id){r.open_escalation_id=null;r.open_escalation_level=null;}else{r.open_escalation_id='ESC-LOCAL-'+Date.now();r.open_escalation_level=r.suggested_escalation_level;}}if(typeof toast==='function')toast(t('saved'));await refresh();}catch(err){if(typeof toast==='function')toast(err.message||'Could not update escalation.');}}

  function notificationText(x){if(x.event_type==='operations_escalation')return `${levelLabel(x.payload?.level)} · ${x.payload?.reason||''}`;return String(x.payload?.status||x.event_type||'Notification').replaceAll('_',' ');}
  function renderNotifications(){const rows=state.notifications||[];const target=document.getElementById('prNotifications');if(!rows.length){target.innerHTML=`<div class="pr-empty">${t('noNotifications')}</div>`;return;}target.innerHTML=`<div class="pr-notifications">${rows.map((x,i)=>`<button type="button" class="pr-note ${x.read_at?'is-read':'is-unread'} priority-${esc(x.priority||'normal')}" data-i="${i}"><span>${x.read_at?t('read'):t('unread')}</span><strong>${esc(notificationText(x))}</strong><small>${new Date(x.created_at).toLocaleString(lang()==='bn'?'bn-BD':'en-US')}</small></button>`).join('')}</div>`;target.querySelectorAll('.pr-note').forEach(b=>b.addEventListener('click',()=>markOne(Number(b.dataset.i))));}

  async function markOne(i){const x=state.notifications[i];if(!x||x.read_at)return;try{if(liveReady())await rpc('mark_notification_read',{p_notification_id:x.notification_id});x.read_at=new Date().toISOString();renderNotifications();renderMetrics();}catch(err){if(typeof toast==='function')toast(err.message||'Could not mark notification read.');}}
  async function markAll(){try{if(liveReady())await rpc('mark_all_notifications_read');state.notifications.forEach(x=>{if(!x.read_at)x.read_at=new Date().toISOString();});renderNotifications();renderMetrics();}catch(err){if(typeof toast==='function')toast(err.message||'Could not mark notifications read.');}}

  function renderPrefs(){const p=state.preferences||{sms_opt_in:false,push_opt_in:false};const f=document.getElementById('prPrefs');f.elements.sms.checked=Boolean(p.sms_opt_in);f.elements.push.checked=Boolean(p.push_opt_in);}
  async function savePrefs(e){e.preventDefault();const sms=e.currentTarget.elements.sms.checked,push=e.currentTarget.elements.push.checked;try{if(liveReady())await rpc('update_my_notification_preferences',{p_sms_opt_in:sms,p_push_opt_in:push,p_quiet_hours_start:null,p_quiet_hours_end:null});state.preferences={sms_opt_in:sms,push_opt_in:push};if(typeof toast==='function')toast(t('saved'));}catch(err){if(typeof toast==='function')toast(err.message||'Could not save notification preferences.');}}

  const observer=new MutationObserver(()=>{if(document.documentElement.lang==='bn'||document.documentElement.lang==='en'){localize();render();}});observer.observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject);else inject();
})();
