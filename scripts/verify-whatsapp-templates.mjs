import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const js=ts.transpile(readFileSync(new URL('../lib/whatsapp.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022});
const {defaultTemplates,messageKinds,fillTemplate,messageValues,whatsappUrl}=await import('data:text/javascript;base64,'+Buffer.from(js).toString('base64'));
const navigatorDescriptor=Object.getOwnPropertyDescriptor(globalThis,'navigator');
try{
 for(const device of [{userAgent:'Mozilla/5.0 (Windows NT 10.0)',maxTouchPoints:0,host:'web.whatsapp.com'},{userAgent:'Mozilla/5.0 (Linux; Android 16)',maxTouchPoints:5,host:'wa.me'},{userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS)',maxTouchPoints:5,host:'wa.me'}]){
  Object.defineProperty(globalThis,'navigator',{configurable:true,value:device});
  for(const tenant of [{name:'Empresa existente',custom:true},{name:'Empresa futura',custom:false}]){
   const data={tenant:{name:tenant.name},settings:{},customers:[{id:'client',name:'Cliente João 👨🏽‍💼 & Ana +',phone:'24999999999'}],services:[{id:'service',name:'Corte ✂️ + Barba 🧔🏽‍♂️'}],professionals:[{id:'pro',name:'Profissional de teste'}]};
   const appointment={customer_id:'client',service_id:'service',professional_id:'pro',starts_at:'2026-10-29T16:30:00Z',price:50,payment_method:'Pix',protocol:'TESTE-UTF8'};
   for(const kind of messageKinds){
    const template=(tenant.custom?'✨ Modelo personalizado de {empresa}\n':'')+defaultTemplates[kind.id];
    const message=fillTemplate(template,messageValues(data,appointment));
    assert(!message.includes('\uFFFD'));assert(!/\{[a-z_]+\}/.test(message));
    for(const detail of ['👋','💈','👤','📅','🕒','✂️','💰','💳','🎫','29/10/2026','13:30','50,00','Pix','TESTE-UTF8',tenant.name])assert(message.includes(detail),detail);
    const url=new URL(whatsappUrl(data.customers[0].phone,message));assert.equal(url.hostname,device.host);
    assert.equal(url.searchParams.get('text'),message);assert.deepEqual(Buffer.from(url.searchParams.get('text'),'utf8'),Buffer.from(message,'utf8'));
    if(tenant.custom)assert(message.startsWith('✨ Modelo personalizado'));
    assert(!new URL(whatsappUrl(data.customers[0].phone,'')).searchParams.has('text'));
   }
  }
 }
}finally{if(navigatorDescriptor)Object.defineProperty(globalThis,'navigator',navigatorDescriptor);else delete globalThis.navigator;}
console.log('PASS: confirmation, cancellation and reschedule; existing custom and future default templates; desktop/iPhone/Android automatic links; exact emoji UTF-8 round-trip; filled customer/date/time/service/price/payment/protocol; clipboard fallback. No real WhatsApp message sent.');
