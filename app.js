(function(){
  'use strict';

  [
    'backend/persistence.css',
    'backend/admin-workflow.css',
    'backend/pilot-readiness.css',
    'backend/market-data.css',
    'backend/mobile-hardening.css',
    'backend/v1-8-hardening.css',
    'backend/v1-8-final-hardening.css',
    'backend/v1-9-operations.css'
  ].forEach(href=>{
    const css=document.createElement('link');
    css.rel='stylesheet';
    css.href=href;
    document.head.appendChild(css);
  });

  function loadScript(src){
    return new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src=src;
      script.onload=resolve;
      script.onerror=()=>reject(new Error('Could not load '+src));
      document.body.appendChild(script);
    });
  }

  async function loadRequired(src){
    try{await loadScript(src);}
    catch(err){
      console.error('Agro-Exchange required module failed',src,err);
      document.documentElement.dataset.axBootFailed='true';
      const banner=document.createElement('div');
      banner.className='ax-module-failure';
      banner.textContent='Agro-Exchange could not start safely. Please refresh and try again. ['+src+']';
      document.body.prepend(banner);
      throw err;
    }
  }

  async function loadFeature(src){
    try{await loadScript(src);}
    catch(err){
      console.error('Agro-Exchange feature module failed',src,err);
      window.AgroV18?.reportModuleFailure?.(src,err);
    }
  }

  async function bootstrap(){
    // The shell, runtime configuration, auth and first v1.8 trust guard are required.
    await loadRequired('app-core.js');
    await loadRequired('backend/runtime-config.js');
    await loadRequired('backend/staging-guard.js');
    await loadRequired('backend/health.js');
    await loadRequired('backend/auth.js');
    await loadRequired('backend/v1-8-hardening.js');

    // Workflow modules are isolated: one failed module must not stop unrelated
    // workflows from loading. The v1.8 guard prevents fake/local transactional
    // success when a required live workflow is unavailable.
    const features=[
      'backend/persistence.js',
      'backend/buyer-workflow.js',
      'backend/trade-workflow.js',
      'backend/qc-workflow.js',
      'backend/logistics-workflow.js',
      'backend/settlement-workflow.js',
      'backend/dispute-workflow.js',
      'backend/admin-workflow.js',
      'backend/pilot-readiness.js',
      'backend/pilot-readiness-visibility.js',
      'backend/market-data.js',
      'backend/pwa.js',
      'backend/v1-9-operations.js'
    ];
    for(const src of features)await loadFeature(src);

    // These final trust layers depend on the workflow DOM existing. Treat them as
    // required because they protect transaction actions and keep economic copy aligned
    // with the live matching implementation.
    await loadRequired('backend/v1-8-final-hardening.js');
    await loadRequired('backend/v1-8-copy-integrity.js');
    window.AgroV18?.refresh?.();
    window.AgroV18Final?.refresh?.();
    window.AgroV18CopyIntegrity?.apply?.();
  }

  bootstrap().catch(err=>console.error('Agro-Exchange bootstrap halted safely',err));
})();
