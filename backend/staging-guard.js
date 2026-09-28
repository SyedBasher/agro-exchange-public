(function(){
  'use strict';

  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  const build=cfg.buildVersion||'1.7';
  const environment=cfg.environment||'staging';

  function text(en,bn){return document.documentElement.lang==='bn'?bn:en;}

  function apply(){
    const notice=document.querySelector('[data-i18n="prototype_notice"]');
    if(notice){
      notice.textContent=text(
        'Controlled pilot · platform listings and transactions are simulated unless explicitly source-labelled',
        'নিয়ন্ত্রিত পাইলট · স্পষ্টভাবে উৎস-চিহ্নিত না হলে প্ল্যাটফর্মের তালিকা ও লেনদেন সিমুলেটেড'
      );
    }

    const corridor=document.querySelector('[data-i18n="corridor_notice"]');
    if(corridor){
      corridor.textContent=text('Bogra–Dhaka controlled staging','বগুড়া–ঢাকা নিয়ন্ত্রিত স্টেজিং');
    }

    const banner=document.querySelector('.prototype-banner .banner-inner');
    if(banner&&!document.getElementById('axStageBadge')){
      const badge=document.createElement('span');
      badge.id='axStageBadge';
      badge.style.cssText='margin-left:auto;font-size:11px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;white-space:nowrap';
      badge.textContent=(environment+' v'+build).toUpperCase();
      banner.appendChild(badge);
    }

    document.documentElement.dataset.axEnvironment=environment;
    document.documentElement.dataset.axBuild=build;
  }

  window.AGRO_DEPLOYMENT_CONTEXT={environment,build};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply);else apply();
  new MutationObserver(apply).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
})();
