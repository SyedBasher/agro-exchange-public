(function(){
  'use strict';
  function lang(){return document.documentElement.lang==='bn'?'bn':'en';}
  function msg(en,bn){return lang()==='bn'?bn:en;}
  function setText(selector,en,bn){const el=document.querySelector(selector);const value=msg(en,bn);if(el&&el.textContent!==value)el.textContent=value;}
  function badge(card){
    if(!card)return;
    let el=card.querySelector('.ax-v18-sim-badge');
    if(!el){el=document.createElement('span');el.className='ax-v18-sim-badge';card.prepend(el);}
    const value=msg('SIMULATED','সিমুলেটেড');if(el.textContent!==value)el.textContent=value;
  }
  function apply(){
    setText('[data-i18n="matches_sub"]',
      'Feasible matches use verified counterparties and are ranked by net economic room, quantity coverage, then timing.',
      'সম্ভাব্য ম্যাচে যাচাইকৃত পক্ষ ব্যবহার করা হয় এবং নিট অর্থনৈতিক ব্যবধান, পরিমাণ কভারেজ ও পরে সময়ের ভিত্তিতে ক্রম দেওয়া হয়।');
    setText('[data-i18n="fulfilment"]',
      'Indicative fulfilment allowance',
      'আনুমানিক পূরণ ব্যয় ভাতা');
    setText('[data-i18n="corridor_economics"]',
      'Illustrative Bogra → Dhaka fulfilment example',
      'বগুড়া → ঢাকা পূরণ ব্যয়ের উদাহরণ');
    setText('[data-i18n="corridor_economics_sub"]',
      'Simulated example only. The live matcher currently uses one indicative route allowance, not observed component costs.',
      'শুধু সিমুলেটেড উদাহরণ। লাইভ ম্যাচার বর্তমানে পর্যবেক্ষিত আলাদা খরচের বদলে একটি আনুমানিক রুট ভাতা ব্যবহার করে।');
    const corridor=document.querySelector('#intelligence .cost-waterfall')?.closest('.card');
    badge(corridor);
  }
  function init(){
    apply();
    window.addEventListener('agro-language-changed',()=>setTimeout(apply,0));
    document.getElementById('langToggle')?.addEventListener('click',()=>setTimeout(apply,0));
  }
  window.AgroV18CopyIntegrity={apply};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();
