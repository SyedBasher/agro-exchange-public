(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  let observer=null;

  function live(){return Boolean(cfg.mode==='supabase'&&cfg.supabaseUrl&&cfg.anonKey&&window.AgroAuth?.getAccessToken?.());}
  function role(){return window.AgroAuth?.getProfile?.()?.role||'';}
  function bn(){return document.documentElement.lang==='bn';}
  function note(kind){
    if(kind==='aggregate')return bn()?'লাইভ সামগ্রিক পাইলট QC মেট্রিক শুধু অনুমোদিত অ্যাডমিন দেখতে পারবেন। এখানে সিমুলেটেড সংখ্যা দেখানো হচ্ছে না।':'Live aggregate pilot QC metrics are available only to an approved admin. Simulated figures are not shown in a live session.';
    if(kind==='exceptions')return bn()?'লাইভ ব্যতিক্রম ও এসকেলেশন তালিকা শুধু অনুমোদিত অ্যাডমিন দেখতে পারবেন।':'The live exception and escalation queue is available only to an approved admin.';
    return bn()?'লাইভ QC খরচ টেলিমেট্রি শুধু QC অপারেটর বা অ্যাডমিন নথিভুক্ত করতে পারবেন।':'Live QC-cost telemetry is available only to a QC operator or admin.';
  }
  function restrict(el,kind){
    if(!el)return;
    const marker='pr-restricted-'+kind;
    const existing=el.querySelector('.'+marker);
    if(existing){existing.textContent=note(kind);return;}
    el.innerHTML=`<div class="pr-empty pr-access-restricted ${marker}">${note(kind)}</div>`;
  }
  function apply(){
    if(!live())return;
    const r=role();
    if(r!=='admin'){
      restrict(document.getElementById('prQcMetrics'),'aggregate');
      restrict(document.getElementById('prExceptions'),'exceptions');
    }
    if(!['qc_operator','admin'].includes(r))restrict(document.getElementById('prQcQueue'),'telemetry');
  }
  function start(){
    apply();
    const root=document.getElementById('pilotReadiness')||document.body;
    if(observer)observer.disconnect();
    observer=new MutationObserver(apply);
    observer.observe(root,{subtree:true,childList:true});
    new MutationObserver(apply).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
    document.addEventListener('agro-auth-changed',apply);
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start);else start();
})();
