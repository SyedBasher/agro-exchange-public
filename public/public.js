const toggle=document.getElementById('langToggle');
let lang=localStorage.getItem('agroPublicLang')||'en';
function applyLanguage(){
  document.documentElement.lang=lang;
  document.querySelectorAll('[data-en][data-bn]').forEach(el=>{el.textContent=el.dataset[lang];});
  toggle.textContent=lang==='en'?'বাংলা':'English';
  localStorage.setItem('agroPublicLang',lang);
}
toggle.addEventListener('click',()=>{lang=lang==='en'?'bn':'en';applyLanguage();});
applyLanguage();
