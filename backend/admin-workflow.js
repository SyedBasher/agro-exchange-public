(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  let state={dashboard:null,profiles:[],organizations:[],exceptions:[],audit:[],sla:[]};

  const copy={
    en:{
      nav:'Operations console',kicker:'PLATFORM OPERATIONS',title:'Admin & operations console',
      sub:'Approve access, monitor stalled workflows and keep an auditable operating trail without changing commercial terms on behalf of users.',
      local:'Operations demo · device only',live:'Live admin console',refresh:'Refresh',
      access:'Access & verification',accessSub:'Operational roles are approval-based. Admin approval changes platform access but does not substitute for a buyer or seller commercial decision.',
      orgs:'Buyer organizations',orgsSub:'Verify organizations before approving buyer accounts.',
      exceptions:'Operational exceptions',exceptionsSub:'Trades are flagged when they remain in a workflow state longer than the pilot operating threshold.',
      audit:'Recent admin audit',auditSub:'Administrative changes are written to a separate append-only operating trail.',
      sla:'Pilot operating thresholds',slaSub:'These are operational monitoring thresholds, not contractual deadlines. They can be tuned as real pilot evidence accumulates.',
      qc:'QC and transaction cost',qcSub:'QC remains part of the platform, but it should not be a blanket high-cost inspection on every trade.',
      qcRule:'Current rule',qcRuleText:'The trade confirmation explicitly records whether QC is required. If both parties agree that QC is not required, the trade now moves directly from confirmation to ready-for-dispatch instead of getting stuck in the QC state.',
      qcApproach:'Pilot cost-control approach',qcApproachText:'Use low-cost evidence and weighing as the baseline; reserve independent or more intensive QC for first-time counterparties, higher-risk or grade-sensitive trades, large values, buyer-requested checks, or cases with a weak reliability history. The exact risk rules should be calibrated from pilot data rather than hard-coded now.',
      unverified:'Unverified users',unverifiedOrgs:'Unverified buyer orgs',activeTrades:'Active trades',stalled:'Stalled trades',disputes:'Active disputes',notifications:'Pending events',qcRequired:'QC-required active',qcBypassed:'QC-bypassed active',
      name:'Name',phone:'Phone',role:'Role',verified:'Verified',organization:'Organization',action:'Action',approve:'Edit access',verify:'Verify',unverify:'Suspend verification',members:'Members',type:'Type',district:'District',
      trade:'Trade',route:'Route',status:'Status',age:'Age',threshold:'Threshold',overdue:'Overdue',qcNeeded:'QC?',yes:'Yes',no:'No',none:'None',
      editAccess:'Edit profile access',verifiedLabel:'Verified account',roleLabel:'Approved role',orgLabel:'Buyer organization',note:'Admin note',save:'Save access',cancel:'Cancel',
      farmer:'Farmer',buyer:'Buyer',field_agent:'Field agent',qc_operator:'QC operator',transporter:'Transporter',admin:'Admin',
      hours:'hours',noProfiles:'No profiles found.',noOrgs:'No buyer organizations found.',noExceptions:'No currently overdue workflow items.',noAudit:'No admin changes recorded yet.',
      simulated:'SIMULATED',saved:'Admin change saved',buyerOrgRequired:'Choose a buyer organization for the buyer role.',notAdmin:'This live screen is restricted to an approved admin account.',
      thresholdHours:'Threshold (hours)',active:'Active',update:'Update',actionName:'Action',when:'When',details:'Details',
      pilotOnly:'Pilot assumption',pilotOnlyText:'The threshold values and QC-routing policy are operating assumptions for testing. They are not market standards and should be revised once real completion times, rejection rates and dispute costs are observed.'
    },
    bn:{
      nav:'অপারেশন কনসোল',kicker:'প্ল্যাটফর্ম অপারেশন',title:'অ্যাডমিন ও অপারেশন কনসোল',
      sub:'অ্যাক্সেস অনুমোদন, আটকে থাকা ওয়ার্কফ্লো পর্যবেক্ষণ এবং ব্যবহারকারীর বাণিজ্যিক সিদ্ধান্ত বদল না করে নিরীক্ষাযোগ্য অপারেশন রেকর্ড রাখুন।',
      local:'অপারেশন ডেমো · শুধু ডিভাইসে',live:'লাইভ অ্যাডমিন কনসোল',refresh:'রিফ্রেশ',
      access:'অ্যাক্সেস ও যাচাই',accessSub:'অপারেশনাল ভূমিকা অনুমোদনভিত্তিক। অ্যাডমিন অ্যাক্সেস পরিবর্তন করতে পারে, কিন্তু ক্রেতা বা বিক্রেতার বাণিজ্যিক সম্মতির বিকল্প হতে পারে না।',
      orgs:'ক্রেতা প্রতিষ্ঠান',orgsSub:'ক্রেতা অ্যাকাউন্ট অনুমোদনের আগে প্রতিষ্ঠান যাচাই করুন।',
      exceptions:'অপারেশনাল ব্যতিক্রম',exceptionsSub:'পাইলট অপারেটিং সীমার চেয়ে বেশি সময় একটি অবস্থায় থাকলে লেনদেন চিহ্নিত হবে।',
      audit:'সাম্প্রতিক অ্যাডমিন অডিট',auditSub:'অ্যাডমিন পরিবর্তন আলাদা অপারেশন রেকর্ডে লেখা হয়।',
      sla:'পাইলট অপারেটিং সীমা',slaSub:'এগুলো অপারেশন পর্যবেক্ষণের সীমা, চুক্তির সময়সীমা নয়। বাস্তব পাইলট তথ্য এলে এগুলো পরিবর্তন করা যাবে।',
      qc:'QC ও লেনদেন ব্যয়',qcSub:'QC থাকবে, তবে প্রতিটি লেনদেনে ব্যয়বহুল পূর্ণাঙ্গ পরিদর্শন বাধ্যতামূলক হওয়া উচিত নয়।',
      qcRule:'বর্তমান নিয়ম',qcRuleText:'লেনদেন নিশ্চিতকরণে QC প্রয়োজন কি না স্পষ্টভাবে লেখা থাকে। উভয় পক্ষ QC প্রয়োজন নেই বলে সম্মত হলে লেনদেন এখন সরাসরি ready-for-dispatch অবস্থায় যাবে।',
      qcApproach:'পাইলটে খরচ নিয়ন্ত্রণ',qcApproachText:'সাধারণ ক্ষেত্রে কম-খরচের ছবি/প্রমাণ ও ওজন ব্যবহার করুন; নতুন পক্ষ, বেশি ঝুঁকি, গ্রেড-সংবেদনশীল বা বড় লেনদেন, ক্রেতার অনুরোধ, অথবা দুর্বল নির্ভরযোগ্যতার ইতিহাসে স্বাধীন বা গভীর QC রাখুন। সুনির্দিষ্ট নিয়ম বাস্তব পাইলট তথ্য থেকে নির্ধারণ করা উচিত।',
      unverified:'অযাচাইকৃত ব্যবহারকারী',unverifiedOrgs:'অযাচাইকৃত ক্রেতা প্রতিষ্ঠান',activeTrades:'সক্রিয় লেনদেন',stalled:'আটকে থাকা লেনদেন',disputes:'সক্রিয় বিরোধ',notifications:'অপেক্ষমাণ ইভেন্ট',qcRequired:'QC-প্রয়োজন সক্রিয়',qcBypassed:'QC-বাইপাস সক্রিয়',
      name:'নাম',phone:'ফোন',role:'ভূমিকা',verified:'যাচাইকৃত',organization:'প্রতিষ্ঠান',action:'করণীয়',approve:'অ্যাক্সেস সম্পাদনা',verify:'যাচাই করুন',unverify:'যাচাই স্থগিত',members:'সদস্য',type:'ধরন',district:'জেলা',
      trade:'লেনদেন',route:'রুট',status:'অবস্থা',age:'সময়',threshold:'সীমা',overdue:'অতিরিক্ত',qcNeeded:'QC?',yes:'হ্যাঁ',no:'না',none:'নেই',
      editAccess:'প্রোফাইল অ্যাক্সেস সম্পাদনা',verifiedLabel:'যাচাইকৃত অ্যাকাউন্ট',roleLabel:'অনুমোদিত ভূমিকা',orgLabel:'ক্রেতা প্রতিষ্ঠান',note:'অ্যাডমিন নোট',save:'অ্যাক্সেস সংরক্ষণ',cancel:'বাতিল',
      farmer:'কৃষক',buyer:'ক্রেতা',field_agent:'ফিল্ড এজেন্ট',qc_operator:'QC অপারেটর',transporter:'পরিবহনকারী',admin:'অ্যাডমিন',
      hours:'ঘণ্টা',noProfiles:'কোনো প্রোফাইল পাওয়া যায়নি।',noOrgs:'কোনো ক্রেতা প্রতিষ্ঠান পাওয়া যায়নি।',noExceptions:'বর্তমানে কোনো ওভারডিউ ওয়ার্কফ্লো নেই।',noAudit:'এখনো কোনো অ্যাডমিন পরিবর্তন রেকর্ড হয়নি।',
      simulated:'সিমুলেটেড',saved:'অ্যাডমিন পরিবর্তন সংরক্ষিত হয়েছে',buyerOrgRequired:'ক্রেতা ভূমিকার জন্য একটি ক্রেতা প্রতিষ্ঠান বেছে নিন।',notAdmin:'লাইভ কনসোল শুধু অনুমোদিত অ্যাডমিন অ্যাকাউন্টের জন্য।',
      thresholdHours:'সীমা (ঘণ্টা)',active:'সক্রিয়',update:'আপডেট',actionName:'করণীয়',when:'সময়',details:'বিস্তারিত',
      pilotOnly:'পাইলট অনুমান',pilotOnlyText:'ওয়ার্কফ্লো সীমা ও QC রাউটিং পরীক্ষামূলক অপারেটিং অনুমান। এগুলো বাজারের মান নয়; বাস্তব সময়, প্রত্যাখ্যান ও বিরোধের খরচ দেখা গেলে সংশোধন করতে হবে।'
    }
  };

  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}
  function token(){return window.AgroAuth?.getAccessToken?.()||'';}
  function profile(){return window.AgroAuth?.getProfile?.()||null;}
  function role(){return profile()?.role||'';}
  function liveReady(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&token());}
  function liveAdmin(){return liveReady()&&role()==='admin';}

  async function rpc(name,body={}){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token(),'Content-Type':'application/json'},body:JSON.stringify(body)});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data?.error||data||('Backend '+r.status));
    return data;
  }

  async function table(path){
    const r=await fetch(String(cfg.supabaseUrl).replace(/\/$/,'')+'/rest/v1/'+path,{headers:{apikey:cfg.anonKey,Authorization:'Bearer '+token()}});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok)throw new Error(data?.message||data||('Backend '+r.status));
    return data;
  }

  function localData(){
    return {
      dashboard:{unverified_profiles:2,unverified_buyer_organizations:1,active_trades:4,stalled_trades:2,active_disputes:1,pending_notifications:7,qc_required_active:3,qc_bypassed_active:1},
      profiles:[
        {profile_id:'demo-p1',display_name:'Shafiq Rahman',phone:'+8801XXXXXXXXX',role:'farmer',verified:false,preferred_language:'bn',buyer_organization_id:null,buyer_organization_name:null,buyer_organization_verified:null},
        {profile_id:'demo-p2',display_name:'Nadia Karim',phone:'+8801XXXXXXXXX',role:'buyer',verified:false,preferred_language:'en',buyer_organization_id:'demo-o1',buyer_organization_name:'Northern Produce Trading',buyer_organization_verified:false},
        {profile_id:'demo-p3',display_name:'Pilot QC Operator',phone:'+8801XXXXXXXXX',role:'qc_operator',verified:true,preferred_language:'bn',buyer_organization_id:null,buyer_organization_name:null,buyer_organization_verified:null}
      ],
      organizations:[
        {buyer_organization_id:'demo-o1',name:'Northern Produce Trading',buyer_type:'wholesaler',verified:false,district:'Dhaka',member_count:1},
        {buyer_organization_id:'demo-o2',name:'Metro Food Distribution',buyer_type:'distributor',verified:true,district:'Dhaka',member_count:2}
      ],
      exceptions:[
        {trade_id:'TR-DEMO-401',confirmation_reference:'AX-DEMO-401',commodity_code:'POTATO',origin_district:'Bogra',destination_district:'Dhaka',trade_status:'awaiting_qc',age_hours:31.4,threshold_hours:24,overdue_hours:7.4,qc_required:true},
        {trade_id:'TR-DEMO-402',confirmation_reference:'AX-DEMO-402',commodity_code:'ONION',origin_district:'Bogra',destination_district:'Dhaka',trade_status:'ready_for_dispatch',age_hours:18.1,threshold_hours:12,overdue_hours:6.1,qc_required:false}
      ],
      audit:[
        {audit_id:'a1',actor_name:'Demo operator',action:'profile_access_updated',target_type:'profile',target_id:'demo-p3',details:{new_role:'qc_operator',new_verified:true},created_at:new Date(Date.now()-3600000).toISOString()}
      ],
      sla:[
        {trade_status:'confirmed',threshold_hours:24,active:true},{trade_status:'awaiting_qc',threshold_hours:24,active:true},{trade_status:'ready_for_dispatch',threshold_hours:12,active:true},{trade_status:'in_transit',threshold_hours:24,active:true},{trade_status:'delivered',threshold_hours:24,active:true},{trade_status:'disputed',threshold_hours:48,active:true}
      ]
    };
  }

  function inject(){
    if(document.getElementById('adminOps'))return;
    const main=document.querySelector('main.content');if(!main)return;
    const section=document.createElement('section');section.id='adminOps';section.className='view';
    section.innerHTML=`
      <div class="page-heading"><div><div class="breadcrumb" data-admin-key="kicker"></div><h1 data-admin-key="title"></h1><p data-admin-key="sub"></p></div><div class="heading-actions"><button id="adminRefresh" class="button secondary" type="button" data-admin-key="refresh"></button></div></div>
      <div class="admin-mode"><strong id="adminMode"></strong><span id="adminRestriction"></span></div>
      <div id="adminMetrics" class="admin-metrics"></div>
      <div class="admin-layout">
        <section class="card admin-wide"><div class="card-head"><div><h2 data-admin-key="access"></h2><p data-admin-key="accessSub"></p></div></div><div id="adminProfiles" class="admin-table-wrap"></div></section>
        <section class="card admin-wide"><div class="card-head"><div><h2 data-admin-key="orgs"></h2><p data-admin-key="orgsSub"></p></div></div><div id="adminOrgs" class="admin-table-wrap"></div></section>
        <section class="card admin-wide"><div class="card-head"><div><h2 data-admin-key="exceptions"></h2><p data-admin-key="exceptionsSub"></p></div></div><div id="adminExceptions" class="admin-table-wrap"></div></section>
        <section class="card admin-qc"><div class="card-head"><div><h2 data-admin-key="qc"></h2><p data-admin-key="qcSub"></p></div></div><div class="admin-qc-body"><div><strong data-admin-key="qcRule"></strong><p data-admin-key="qcRuleText"></p></div><div><strong data-admin-key="qcApproach"></strong><p data-admin-key="qcApproachText"></p></div><div class="admin-pilot-note"><strong data-admin-key="pilotOnly"></strong><p data-admin-key="pilotOnlyText"></p></div></div></section>
        <section class="card admin-sla"><div class="card-head"><div><h2 data-admin-key="sla"></h2><p data-admin-key="slaSub"></p></div></div><div id="adminSla"></div></section>
        <section class="card admin-wide"><div class="card-head"><div><h2 data-admin-key="audit"></h2><p data-admin-key="auditSub"></p></div></div><div id="adminAudit" class="admin-table-wrap"></div></section>
      </div>`;
    main.appendChild(section);

    const nav=document.querySelector('.secondary-nav');
    if(nav&&!document.querySelector('[data-view="adminOps"]')){
      const btn=document.createElement('button');btn.className='side-link';btn.dataset.view='adminOps';btn.innerHTML='<span class="nav-icon">⚙</span><span data-admin-nav></span>';nav.appendChild(btn);btn.addEventListener('click',show);
    }
    document.getElementById('adminRefresh').addEventListener('click',refresh);
    injectModal();localize();refresh();
  }

  function injectModal(){
    if(document.getElementById('adminAccessModal'))return;
    const m=document.createElement('div');m.id='adminAccessModal';m.className='admin-modal';m.innerHTML=`<div class="admin-backdrop" data-admin-close></div><section class="admin-sheet"><button class="admin-close" data-admin-close type="button">×</button><div class="section-kicker" data-admin-key="kicker"></div><h2 data-admin-key="editAccess"></h2><form id="adminAccessForm" class="admin-form"><input type="hidden" name="profileId"><label><span data-admin-key="verifiedLabel"></span><select name="verified"><option value="true" data-admin-key="yes"></option><option value="false" data-admin-key="no"></option></select></label><label><span data-admin-key="roleLabel"></span><select name="role"><option value="farmer" data-admin-key="farmer"></option><option value="buyer" data-admin-key="buyer"></option><option value="field_agent" data-admin-key="field_agent"></option><option value="qc_operator" data-admin-key="qc_operator"></option><option value="transporter" data-admin-key="transporter"></option><option value="admin" data-admin-key="admin"></option></select></label><label class="admin-wide-field"><span data-admin-key="orgLabel"></span><select name="org"></select></label><label class="admin-wide-field"><span data-admin-key="note"></span><textarea name="note" maxlength="400"></textarea></label><div class="admin-modal-actions"><button class="button secondary" type="button" data-admin-close data-admin-key="cancel"></button><button class="button primary" type="submit" data-admin-key="save"></button></div></form></section>`;document.body.appendChild(m);m.querySelectorAll('[data-admin-close]').forEach(x=>x.addEventListener('click',closeModal));document.getElementById('adminAccessForm').addEventListener('submit',saveProfileAccess);
  }

  function show(){document.querySelectorAll('.view').forEach(v=>v.classList.remove('active-view'));document.getElementById('adminOps')?.classList.add('active-view');document.querySelectorAll('.side-link[data-view]').forEach(b=>b.classList.toggle('active',b.dataset.view==='adminOps'));document.querySelector('.sidebar')?.classList.remove('open');document.getElementById('mobileOverlay')?.classList.remove('show');window.scrollTo({top:0,behavior:'smooth'});refresh();}
  function closeModal(){document.getElementById('adminAccessModal')?.classList.remove('open');}
  function localize(){document.querySelectorAll('#adminOps [data-admin-key],#adminAccessModal [data-admin-key]').forEach(el=>el.textContent=t(el.dataset.adminKey));document.querySelectorAll('[data-admin-nav]').forEach(el=>el.textContent=t('nav'));const mode=document.getElementById('adminMode');if(mode)mode.textContent=liveAdmin()?t('live'):t('local');const restriction=document.getElementById('adminRestriction');if(restriction)restriction.textContent=liveReady()&&!liveAdmin()?t('notAdmin'):'';}

  async function refresh(){
    localize();
    if(liveReady()&&!liveAdmin()){
      state=localData();render();return;
    }
    if(!liveAdmin()){state=localData();render();return;}
    try{
      const [d,p,o,e,a,s]=await Promise.all([
        rpc('get_admin_dashboard'),rpc('get_admin_profiles'),rpc('get_admin_buyer_organizations'),rpc('get_admin_exception_queue'),rpc('get_admin_audit_log',{p_limit:50}),table('operations_sla_rules?select=trade_status,threshold_hours,active,note&order=trade_status.asc')
      ]);
      state={dashboard:Array.isArray(d)?d[0]:d,profiles:p||[],organizations:o||[],exceptions:e||[],audit:a||[],sla:s||[]};render();
    }catch(err){state=localData();render();if(typeof toast==='function')toast(err.message||'Could not load live admin data.');}
  }

  function metric(label,value){return `<article><span>${label}</span><strong>${Number(value||0).toLocaleString(lang()==='bn'?'bn-BD':'en-US')}</strong></article>`;}
  function render(){renderMetrics();renderProfiles();renderOrgs();renderExceptions();renderSla();renderAudit();}
  function renderMetrics(){const d=state.dashboard||{};document.getElementById('adminMetrics').innerHTML=[metric(t('unverified'),d.unverified_profiles),metric(t('unverifiedOrgs'),d.unverified_buyer_organizations),metric(t('activeTrades'),d.active_trades),metric(t('stalled'),d.stalled_trades),metric(t('disputes'),d.active_disputes),metric(t('notifications'),d.pending_notifications),metric(t('qcRequired'),d.qc_required_active),metric(t('qcBypassed'),d.qc_bypassed_active)].join('');}

  function renderProfiles(){const target=document.getElementById('adminProfiles');if(!state.profiles.length){target.innerHTML=`<div class="admin-empty">${t('noProfiles')}</div>`;return;}target.innerHTML=`<table class="admin-table"><thead><tr><th>${t('name')}</th><th>${t('phone')}</th><th>${t('role')}</th><th>${t('verified')}</th><th>${t('organization')}</th><th>${t('action')}</th></tr></thead><tbody>${state.profiles.map((p,i)=>`<tr><td><strong>${esc(p.display_name||'—')}</strong>${!liveAdmin()?`<small>${t('simulated')}</small>`:''}</td><td>${esc(p.phone||'—')}</td><td>${esc(t(p.role)||p.role)}</td><td>${p.verified?t('yes'):t('no')}</td><td>${esc(p.buyer_organization_name||'—')}</td><td><button class="button secondary admin-profile-edit" data-i="${i}" type="button">${t('approve')}</button></td></tr>`).join('')}</tbody></table>`;target.querySelectorAll('.admin-profile-edit').forEach(b=>b.addEventListener('click',()=>openProfile(Number(b.dataset.i))));}

  function renderOrgs(){const target=document.getElementById('adminOrgs');if(!state.organizations.length){target.innerHTML=`<div class="admin-empty">${t('noOrgs')}</div>`;return;}target.innerHTML=`<table class="admin-table"><thead><tr><th>${t('name')}</th><th>${t('type')}</th><th>${t('district')}</th><th>${t('members')}</th><th>${t('verified')}</th><th>${t('action')}</th></tr></thead><tbody>${state.organizations.map((o,i)=>`<tr><td><strong>${esc(o.name)}</strong></td><td>${esc(o.buyer_type||'—')}</td><td>${esc(o.district||'—')}</td><td>${Number(o.member_count||0)}</td><td>${o.verified?t('yes'):t('no')}</td><td><button class="button secondary admin-org-toggle" data-i="${i}" type="button">${o.verified?t('unverify'):t('verify')}</button></td></tr>`).join('')}</tbody></table>`;target.querySelectorAll('.admin-org-toggle').forEach(b=>b.addEventListener('click',()=>toggleOrg(Number(b.dataset.i))));}

  function renderExceptions(){const target=document.getElementById('adminExceptions');if(!state.exceptions.length){target.innerHTML=`<div class="admin-empty">${t('noExceptions')}</div>`;return;}target.innerHTML=`<table class="admin-table"><thead><tr><th>${t('trade')}</th><th>${t('route')}</th><th>${t('status')}</th><th>${t('age')}</th><th>${t('threshold')}</th><th>${t('overdue')}</th><th>${t('qcNeeded')}</th></tr></thead><tbody>${state.exceptions.map(x=>`<tr><td><strong>${esc(x.confirmation_reference||x.trade_id)}</strong><small>${esc(x.commodity_code||'')}</small></td><td>${esc(x.origin_district)} → ${esc(x.destination_district)}</td><td>${esc(x.trade_status)}</td><td>${esc(x.age_hours)} ${t('hours')}</td><td>${esc(x.threshold_hours)} ${t('hours')}</td><td><strong>${esc(x.overdue_hours)} ${t('hours')}</strong></td><td>${x.qc_required?t('yes'):t('no')}</td></tr>`).join('')}</tbody></table>`;}

  function renderSla(){const target=document.getElementById('adminSla');target.innerHTML=state.sla.map((r,i)=>`<form class="admin-sla-row" data-i="${i}"><strong>${esc(r.trade_status)}</strong><label><span>${t('thresholdHours')}</span><input name="hours" type="number" min="1" step="1" value="${Number(r.threshold_hours||1)}"></label><label class="admin-sla-check"><input name="active" type="checkbox" ${r.active?'checked':''}><span>${t('active')}</span></label><button class="button secondary" type="submit">${t('update')}</button></form>`).join('');target.querySelectorAll('.admin-sla-row').forEach(f=>f.addEventListener('submit',saveSla));}

  function renderAudit(){const target=document.getElementById('adminAudit');if(!state.audit.length){target.innerHTML=`<div class="admin-empty">${t('noAudit')}</div>`;return;}target.innerHTML=`<table class="admin-table"><thead><tr><th>${t('when')}</th><th>${t('name')}</th><th>${t('actionName')}</th><th>${t('details')}</th></tr></thead><tbody>${state.audit.map(a=>`<tr><td>${new Date(a.created_at).toLocaleString(lang()==='bn'?'bn-BD':'en-US')}</td><td>${esc(a.actor_name||'—')}</td><td>${esc(a.action)}</td><td><code>${esc(JSON.stringify(a.details||{}))}</code></td></tr>`).join('')}</tbody></table>`;}

  function openProfile(i){const p=state.profiles[i];if(!p)return;const f=document.getElementById('adminAccessForm');f.elements.profileId.value=p.profile_id;f.elements.verified.value=String(Boolean(p.verified));f.elements.role.value=p.role||'farmer';const org=f.elements.org;org.innerHTML=`<option value="">— ${t('none')} —</option>`+state.organizations.map(o=>`<option value="${esc(o.buyer_organization_id)}">${esc(o.name)}${o.verified?' ✓':''}</option>`).join('');org.value=p.buyer_organization_id||'';f.elements.note.value='';document.getElementById('adminAccessModal').classList.add('open');}

  async function saveProfileAccess(e){e.preventDefault();const f=e.currentTarget;const pid=f.elements.profileId.value,verified=f.elements.verified.value==='true',r=f.elements.role.value,org=f.elements.org.value||null;if(r==='buyer'&&!org){if(typeof toast==='function')toast(t('buyerOrgRequired'));return;}try{if(liveAdmin())await rpc('admin_update_profile_access',{p_profile_id:pid,p_verified:verified,p_role:r,p_buyer_organization_id:org,p_note:String(f.elements.note.value||'')||null});else{const p=state.profiles.find(x=>x.profile_id===pid);if(p){p.verified=verified;p.role=r;const o=state.organizations.find(x=>x.buyer_organization_id===org);p.buyer_organization_id=org;p.buyer_organization_name=o?.name||null;p.buyer_organization_verified=o?.verified??null;}state.dashboard.unverified_profiles=state.profiles.filter(x=>!x.verified).length;}closeModal();if(typeof toast==='function')toast(t('saved'));await refresh();}catch(err){if(typeof toast==='function')toast(err.message||'Could not save access.');}}

  async function toggleOrg(i){const o=state.organizations[i];if(!o)return;try{if(liveAdmin())await rpc('admin_update_buyer_organization',{p_buyer_organization_id:o.buyer_organization_id,p_verified:!o.verified,p_note:null});else{o.verified=!o.verified;state.dashboard.unverified_buyer_organizations=state.organizations.filter(x=>!x.verified).length;}if(typeof toast==='function')toast(t('saved'));await refresh();}catch(err){if(typeof toast==='function')toast(err.message||'Could not update organization.');}}

  async function saveSla(e){e.preventDefault();const i=Number(e.currentTarget.dataset.i),r=state.sla[i],hours=Number(e.currentTarget.elements.hours.value),active=e.currentTarget.elements.active.checked;if(!r||!Number.isFinite(hours)||hours<=0)return;try{if(liveAdmin())await rpc('admin_update_sla_rule',{p_trade_status:r.trade_status,p_threshold_hours:hours,p_active:active,p_note:null});else{r.threshold_hours=hours;r.active=active;}if(typeof toast==='function')toast(t('saved'));await refresh();}catch(err){if(typeof toast==='function')toast(err.message||'Could not update threshold.');}}

  const observer=new MutationObserver(()=>{if(document.documentElement.lang==='bn'||document.documentElement.lang==='en'){localize();render();}});observer.observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject);else inject();
})();
