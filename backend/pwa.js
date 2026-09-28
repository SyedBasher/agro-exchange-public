(function(){
  'use strict';

  function text(en,bn){return document.documentElement.lang==='bn'?bn:en;}

  function ensureManifest(){
    if(document.querySelector('link[rel="manifest"]'))return;
    const link=document.createElement('link');link.rel='manifest';link.href='manifest.webmanifest';document.head.appendChild(link);
  }

  function ensureAppleMeta(){
    if(!document.querySelector('meta[name="apple-mobile-web-app-capable"]')){
      const m=document.createElement('meta');m.name='apple-mobile-web-app-capable';m.content='yes';document.head.appendChild(m);
    }
  }

  function showNetworkState(){
    let chip=document.getElementById('axNetworkState');
    if(!chip){chip=document.createElement('div');chip.id='axNetworkState';chip.className='ax-network-state';document.body.appendChild(chip);}
    const offline=!navigator.onLine;
    const backend=window.AGRO_BACKEND_STATUS;
    const backendUnavailable=!offline&&backend&&backend.connected===false;

    if(offline){
      chip.textContent=text('Offline · live data unavailable','অফলাইন · লাইভ তথ্য পাওয়া যাচ্ছে না');
      chip.hidden=false;
    }else if(backendUnavailable){
      chip.textContent=text('Live database unavailable · transaction actions are disabled','লাইভ ডেটাবেজ পাওয়া যাচ্ছে না · লেনদেনের কাজ বন্ধ আছে');
      chip.hidden=false;
    }else{
      chip.textContent=text('Online','অনলাইন');
      chip.hidden=true;
    }
    chip.classList.toggle('is-offline',offline||backendUnavailable);
    chip.classList.toggle('is-online',!offline&&!backendUnavailable);
  }

  async function register(){
    ensureManifest();ensureAppleMeta();showNetworkState();
    if(!('serviceWorker' in navigator))return;
    if(location.protocol!=='https:'&&location.hostname!=='localhost'&&location.hostname!=='127.0.0.1')return;
    try{await navigator.serviceWorker.register('sw.js',{scope:'./'});}catch(err){console.warn('Agro-Exchange service worker registration failed',err);}
  }

  window.addEventListener('online',()=>{showNetworkState();window.AgroHealth?.check?.();});
  window.addEventListener('offline',showNetworkState);
  window.addEventListener('agro-backend-status',showNetworkState);
  window.addEventListener('agro-language-changed',showNetworkState);
  new MutationObserver(showNetworkState).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',register);else register();
})();
