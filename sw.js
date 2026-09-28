const CACHE_NAME='agro-exchange-shell-v1.10';
const SHELL=[
  './','./index.html','./styles.css','./app.js','./app-core.js','./manifest.webmanifest','./offline.html','./diagnostics.html',
  './public/index.html','./public/public.css','./public/public.js',
  './assets/agro-exchange-icon.svg','./assets/agro-exchange-icon-192.png','./assets/agro-exchange-icon-512.png',
  './backend/persistence.css','./backend/admin-workflow.css','./backend/pilot-readiness.css','./backend/market-data.css','./backend/mobile-hardening.css','./backend/v1-8-hardening.css','./backend/v1-8-final-hardening.css','./backend/v1-9-operations.css',
  './backend/runtime-config.js','./backend/staging-guard.js','./backend/health.js','./backend/auth.js','./backend/v1-8-hardening.js','./backend/v1-8-final-hardening.js','./backend/v1-8-copy-integrity.js','./backend/persistence.js','./backend/buyer-workflow.js',
  './backend/trade-workflow.js','./backend/qc-workflow.js','./backend/logistics-workflow.js',
  './backend/settlement-workflow.js','./backend/dispute-workflow.js','./backend/admin-workflow.js','./backend/pilot-readiness.js',
  './backend/pilot-readiness-visibility.js','./backend/market-data.js','./backend/pwa.js','./backend/v1-9-operations.js'
];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',event=>{
  event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE_NAME).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));
});

function isBackendRequest(url){
  return url.hostname.endsWith('.supabase.co') || url.pathname.includes('/rest/v1/') || url.pathname.includes('/auth/v1/') || url.pathname.includes('/storage/v1/');
}

function navigationFallback(url){
  if(url.pathname.includes('/public/'))return './public/index.html';
  if(url.pathname.endsWith('/diagnostics.html'))return './diagnostics.html';
  return './index.html';
}

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);
  if(isBackendRequest(url))return;
  // Build freshness probes must never create timestamped cache entries.
  if(url.origin===self.location.origin && url.pathname.endsWith('/backend/runtime-config.js') && url.searchParams.has('ax_build_check')){
    event.respondWith(fetch(req,{cache:'no-store'}));
    return;
  }

  if(req.mode==='navigate'){
    event.respondWith(
      fetch(req).catch(()=>caches.match(navigationFallback(url)).then(r=>r||caches.match('./offline.html')))
    );
    return;
  }

  if(url.origin===self.location.origin){
    event.respondWith(caches.match(req).then(cached=>{
      const network=fetch(req).then(res=>{
        if(res&&res.ok){const copy=res.clone();caches.open(CACHE_NAME).then(c=>c.put(req,copy));}
        return res;
      }).catch(()=>cached);
      return cached||network;
    }));
  }
});
