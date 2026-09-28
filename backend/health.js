(function(){
  'use strict';
  const cfg=window.AGRO_EXCHANGE_CONFIG||{};
  if(cfg.mode!=='supabase'||!cfg.supabaseUrl||!cfg.anonKey)return;

  const base=String(cfg.supabaseUrl).replace(/\/$/,'');
  let timer=null;

  function text(en,bn){return document.documentElement.lang==='bn'?bn:en;}

  function render(status){
    const banner=document.querySelector('.prototype-banner .banner-inner');
    if(!banner)return;
    let tag=document.getElementById('axBackendStatus');
    if(!tag){
      tag=document.createElement('span');
      tag.id='axBackendStatus';
      tag.className='backend-status';
      banner.appendChild(tag);
    }
    tag.dataset.connected=String(Boolean(status.connected));
    if(status.connected){
      tag.textContent=text('• Database connected','• ডেটাবেজ সংযুক্ত');
      tag.classList.remove('is-unavailable');
    }else if(status.reason==='offline'){
      tag.textContent=text('• Offline','• অফলাইন');
      tag.classList.add('is-unavailable');
    }else{
      tag.textContent=text('• Live database unavailable','• লাইভ ডেটাবেজ পাওয়া যাচ্ছে না');
      tag.classList.add('is-unavailable');
    }
  }

  function publish(status){
    window.AGRO_BACKEND_STATUS={...status,checkedAt:new Date().toISOString()};
    render(window.AGRO_BACKEND_STATUS);
    window.dispatchEvent(new CustomEvent('agro-backend-status',{detail:window.AGRO_BACKEND_STATUS}));
  }

  async function check(){
    if(!navigator.onLine){publish({connected:false,reason:'offline'});return false;}
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(),8000);
    try{
      const res=await fetch(base+'/rest/v1/commodities?select=code&limit=1',{
        headers:{apikey:cfg.anonKey},signal:controller.signal,cache:'no-store'
      });
      if(!res.ok)throw new Error('HTTP '+res.status);
      const rows=await res.json();
      publish({connected:true,reason:'ok',rows:Array.isArray(rows)?rows.length:0});
      return true;
    }catch(error){
      publish({connected:false,reason:'backend',error:String(error)});
      console.warn('Agro-Exchange backend health check failed',error);
      return false;
    }finally{clearTimeout(timeout);}
  }

  function schedule(){
    clearInterval(timer);
    timer=setInterval(()=>{if(document.visibilityState==='visible')check();},60000);
  }

  window.addEventListener('online',check);
  window.addEventListener('offline',()=>publish({connected:false,reason:'offline'}));
  document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible')check();});
  window.addEventListener('agro-language-changed',()=>render(window.AGRO_BACKEND_STATUS||{connected:false,reason:navigator.onLine?'backend':'offline'}));

  window.AgroHealth={check,getStatus:()=>window.AGRO_BACKEND_STATUS||null};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{check();schedule();});
  else{check();schedule();}
})();
