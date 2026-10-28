import assert from 'node:assert/strict';
import ts from 'typescript';
import {readFileSync} from 'node:fs';
async function load(path){const code=ts.transpile(readFileSync(new URL(path,import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022});return import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));}
const {availableSharePlans,plansWhatsAppMessage}=await load('../lib/plan-sharing.ts');
const {whatsappUrl,whatsappTarget:planWhatsAppTarget}=await load('../lib/whatsapp.ts');
const description='📅 👋 💳 💰 🔄 📋 ✅ ✂️ 👨🏽‍💼\nDescrição & preços + 100% de atenção à ação';
const plans=[{id:'monthly',name:'Básico',amount:49.9,months:1,description,active:true},{id:'annual',name:'Anual',amount:499.9,months:12,description:'📲 Aplicativo',active:true},{id:'gone',name:'Excluído',amount:1,months:1,active:true,deleted_at:'2026-01-01'},{id:'off',name:'Inativo',amount:1,months:1,active:false}];
assert.equal(availableSharePlans(plans).length,2);
const message=plansWhatsAppMessage(plans,'João 👨🏽‍💼');
assert(message.includes(description));assert(!message.includes('\uFFFD'));assert(message.includes('49,90 por mês'));assert(message.includes('499,90 por ano'));assert(!message.includes('Excluído'));assert(!message.includes('Inativo'));
for(const target of ['web','app']){
 const url=new URL(whatsappUrl('(24) 99999-9999',message,target));
 assert.equal(url.searchParams.get('text'),message,'Unicode and reserved characters must survive decoding exactly');
 assert.equal(Buffer.from(url.searchParams.get('text'),'utf8').toString('hex'),Buffer.from(message,'utf8').toString('hex'));
 assert(!url.searchParams.get('text').includes('\uFFFD'));
 const chat=new URL(whatsappUrl('(24) 99999-9999','',target));assert(!chat.searchParams.has('text'),'clipboard fallback must not transport text in the link');
 if(target==='web'){assert.equal(url.hostname,'web.whatsapp.com');assert.equal(url.pathname,'/send');assert.equal(url.searchParams.get('phone'),'5524999999999');}else assert.equal(url.hostname,'wa.me');
}
assert.equal(planWhatsAppTarget('Mozilla/5.0 (Windows NT 10.0; Win64; x64)'),'web');
assert.equal(planWhatsAppTarget('Mozilla/5.0 (Macintosh; Intel Mac OS X)',0),'web');
assert.equal(planWhatsAppTarget('Mozilla/5.0 (Macintosh; Intel Mac OS X)',5),'app');
assert.equal(planWhatsAppTarget('Mozilla/5.0 (iPhone; CPU iPhone OS)'),'app');
assert.equal(planWhatsAppTarget('Mozilla/5.0 (Linux; Android 16)'),'app');
assert.equal(whatsappUrl('123',message,'web'),'');assert.equal(plansWhatsAppMessage([]),'');
console.log('PASS: desktop direct Web URL, mobile URLs, UTF-8 byte round-trip with emojis/ZWJ/skin tones/accents, clipboard fallback without text URL, plan filtering and invalid phone rejection. External WhatsApp rendering is not covered.');
