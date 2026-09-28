(function(){
  'use strict';
  const key='agro_exchange_trade_confirmations_v1';
  try{
    const rows=JSON.parse(localStorage.getItem(key)||'[]');
    if(!rows.some(x=>x&&x.tradeId==='TR-DEMO-SET-001')&&!rows.some(x=>x&&['delivered','settled','disputed'].includes(x.tradeStatus))){
      rows.unshift({
        id:'CONF-DEMO-SET-001',reference:'AX-DEMO-SET-001',status:'confirmed',tradeId:'TR-DEMO-SET-001',tradeStatus:'delivered',
        commodity:'Potato',origin:'Bogra',destination:'Dhaka',quantityKg:5000,price:31.5,qcRequired:true,
        sellerAccepted:true,buyerAccepted:true,source:'demo',confirmedAt:new Date().toISOString(),deliveryDue:new Date().toISOString()
      });
      localStorage.setItem(key,JSON.stringify(rows.slice(0,100)));
    }
  }catch(err){console.warn('Could not seed local settlement demo',err);}
})();
