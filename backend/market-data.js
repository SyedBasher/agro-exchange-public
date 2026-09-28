(function(){
  'use strict';
  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  let rows=[];

  const copy={
    en:{title:'Official source snapshot',sub:'Source-backed observations are kept separate from simulated pilot listings and verified platform trades.',source:'Source',retrieved:'Retrieved',range:'Published range',status:'Data status',raw:'Source capture · not promoted',note:'The captured DAM headline did not identify a specific market or effective date. These values are preserved as a raw official-source snapshot and are not treated as verified market observations.',open:'Open official report',empty:'No source-backed snapshot is available yet.',official:'Official source',mapping:'Commodity mapped; geography/date pending'},
    bn:{title:'সরকারি উৎসের স্ন্যাপশট',sub:'উৎসভিত্তিক তথ্যকে সিমুলেটেড পাইলট লিস্টিং ও যাচাইকৃত প্ল্যাটফর্ম ট্রেড থেকে আলাদা রাখা হয়।',source:'উৎস',retrieved:'সংগ্রহের সময়',range:'প্রকাশিত রেঞ্জ',status:'ডেটার অবস্থা',raw:'উৎস স্ন্যাপশট · যাচাইকৃত বাজার পর্যবেক্ষণ নয়',note:'সংরক্ষিত DAM হেডলাইনে নির্দিষ্ট বাজার বা কার্যকর তারিখ স্পষ্ট ছিল না। তাই মানগুলো সরকারি উৎসের কাঁচা স্ন্যাপশট হিসেবে রাখা হয়েছে; যাচাইকৃত বাজার পর্যবেক্ষণ হিসেবে ব্যবহার করা হয়নি।',open:'সরকারি রিপোর্ট খুলুন',empty:'এখনো কোনো উৎসভিত্তিক স্ন্যাপশট পাওয়া যায়নি।',official:'সরকারি উৎস',mapping:'পণ্য ম্যাপ করা; বাজার/তারিখ অপেক্ষমাণ'}
  };
  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function t(k){return copy[lang()][k]||k;}
  function esc(v){return String(v??'').replace(/[&<>\"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c]));}
  function fmtTime(v){if(!v)return '—';try{return new Intl.DateTimeFormat(lang()==='bn'?'bn-BD':'en-GB',{dateStyle:'medium',timeStyle:'short'}).format(new Date(v));}catch{return String(v);}}

  async function load(){
    if(!(cfg.supabaseUrl&&cfg.anonKey))return [];
    const base=String(cfg.supabaseUrl).replace(/\/$/,'');
    const url=base+'/rest/v1/market_source_snapshot_view?select=source_record_id,source_code,source_name,publisher,authority_class,report_url,source_url,retrieved_at,effective_date,commodity_label,commodity_code,grade_label,geography_label,price_type,price_low,price_high,unit_text,mapping_status&order=retrieved_at.desc,source_record_id.asc&limit=20';
    const headers={apikey:cfg.anonKey};
    const tok=window.AgroAuth?.getAccessToken?.();if(tok)headers.Authorization='Bearer '+tok;
    const r=await fetch(url,{headers});if(!r.ok)throw new Error('Market source '+r.status);return await r.json();
  }

  function inject(){
    const view=document.getElementById('markets');if(!view||document.getElementById('axSourceSnapshot'))return;
    const card=document.createElement('section');card.id='axSourceSnapshot';card.className='card ax-source-card';
    const firstCard=view.querySelector(':scope > .card');
    if(firstCard)view.insertBefore(card,firstCard);else view.appendChild(card);
    render();refresh();
  }

  function render(){
    const el=document.getElementById('axSourceSnapshot');if(!el)return;
    if(!rows.length){el.innerHTML=`<div class="ax-source-head"><div><span class="ax-source-kicker">${t('official')}</span><h2>${t('title')}</h2><p>${t('sub')}</p></div></div><div class="ax-source-empty">${t('empty')}</div>`;return;}
    const latest=rows[0],same=rows.filter(r=>r.source_url===latest.source_url&&r.retrieved_at===latest.retrieved_at);
    el.innerHTML=`<div class="ax-source-head"><div><span class="ax-source-kicker">${t('official')}</span><h2>${t('title')}</h2><p>${t('sub')}</p></div><a class="button secondary ax-source-link" href="${esc(latest.report_url||latest.source_url)}" target="_blank" rel="noopener noreferrer">${t('open')}</a></div>
      <div class="ax-source-meta"><div><span>${t('source')}</span><strong>${esc(latest.publisher||latest.source_name)}</strong></div><div><span>${t('retrieved')}</span><strong>${esc(fmtTime(latest.retrieved_at))}</strong></div><div><span>${t('status')}</span><strong>${t('raw')}</strong></div></div>
      <div class="ax-source-note">${t('note')}</div>
      <div class="ax-source-table"><table><thead><tr><th>${lang()==='bn'?'পণ্য':'Commodity'}</th><th>${lang()==='bn'?'গ্রেড/ধরন':'Grade / type'}</th><th>${t('range')}</th><th>${t('status')}</th></tr></thead><tbody>${same.map(r=>`<tr><td><strong>${esc(r.commodity_label)}</strong></td><td>${esc(r.grade_label||'—')}</td><td>${r.price_low==null&&r.price_high==null?'—':`${esc(r.price_low??r.price_high)}–${esc(r.price_high??r.price_low)} ${esc(r.unit_text||'')}`}</td><td><span class="ax-source-status">${t('mapping')}</span></td></tr>`).join('')}</tbody></table></div>`;
  }

  async function refresh(){try{rows=await load();render();}catch(err){console.warn('Agro-Exchange source snapshot unavailable',err);}}
  new MutationObserver(()=>render()).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject);else inject();
})();
