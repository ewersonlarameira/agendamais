import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const transpile=p=>ts.transpile(readFileSync(new URL(p,import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022});
const cryptoURL='data:text/javascript;base64,'+Buffer.from(transpile('../supabase/functions/agenda-backup/crypto.ts')).toString('base64');
const {seal,unseal}=await import(cryptoURL);
const handlerURL='data:text/javascript;base64,'+Buffer.from(transpile('../supabase/functions/agenda-backup/handler.ts').replace("'./crypto.ts'",JSON.stringify(cryptoURL))).toString('base64');
const {backupHandler}=await import(handlerURL);
const password='fixture-only-backup-passphrase';
const data={format:'agenda-complete-data',version:1,exported_at:'2026-10-28T12:00:00Z',tables:{customers:[{name:'Cliente 🧑🏽‍💼',notes:'Histórico íntegro'}],appointments:['Agendado','Confirmado','Concluído','Cancelado','Não compareceu','Bloqueado'].map(status=>({status}))},accounts:[{encrypted_password:'fixture-hash'}],identities:[],objects:[{bucket:'branding',path:'fixture/logo.png',mime:'image/png'}]};
const png=new Uint8Array([137,80,78,71,13,10,26,10]);let master=true;let validUser=true;let storageExists=true;let calls=[];
const fetcher=async(url,opts={})=>{calls.push({url,opts});if(url.endsWith('/auth/v1/user'))return Response.json({id:'fixture-master'},{status:validUser?200:401});if(url.endsWith('/agenda_recovery_access'))return Response.json(master);if(url.endsWith('/agenda_recovery_service')){const b=JSON.parse(opts.body);if(b.op==='export')return Response.json(data);if(b.op==='preview')return Response.json({ticket:'fixture-ticket',counts:{appointments:{backup:6,missing:2,preserved:4}}});if(b.op==='authorize')return Response.json({ok:true});if(b.op==='restore')return Response.json({ok:true,counts:{appointments:{inserted:2}}});}if(url.includes('/object/authenticated/'))return storageExists?new Response(png):Response.json({error:'absent'},{status:404});if(url.includes('/object/branding/'))return Response.json({ok:true});throw Error('Unexpected request');};
const handler=backupHandler({url:'https://fixture.example',serviceKey:'fixture-secret'},fetcher);
async function run(body,token=true){return handler(new Request('https://fixture.example',{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer fixture-token'}:{})},body:JSON.stringify(body)}));}
assert.equal((await run({op:'export'},false)).status,401);validUser=false;assert.equal((await run({op:'export'})).status,401);validUser=true;master=false;assert.equal((await run({op:'export'})).status,403);master=true;
const r=await run({op:'export',passphrase:password});assert.equal(r.status,200);const {archive,summary}=await r.json();assert.equal(summary.appointments,6);const payload=await unseal(archive,password);assert.deepEqual(payload.data,data);assert(!JSON.stringify(archive).includes('fixture-hash'));
await assert.rejects(unseal(archive,'incorrect-password-123'));await assert.rejects(unseal({...archive,ciphertext:archive.ciphertext.slice(0,-4)+'AAAA'},password));
calls=[];const preview=await run({op:'preview',archive,passphrase:password});assert.equal(preview.status,200);assert(!calls.some(c=>c.opts.method==='POST'&&c.url.includes('/object/')));
assert.equal((await run({op:'restore',archive,passphrase:password,ticket:'fixture-ticket',confirmation:'wrong'})).status,400);
for(const exists of [true,false]){storageExists=exists;calls=[];const restored=await run({op:'restore',archive,passphrase:password,ticket:'fixture-ticket',confirmation:'RESTAURAR'});assert.equal(restored.status,200);const writes=calls.filter(c=>c.opts.method==='POST'&&c.url.includes('/object/'));assert.equal(writes.length,exists?0:1);for(const c of writes)assert.equal(c.opts.headers['x-upsert'],'false');}
const foreign=await seal({...payload,project:'other-project'},password);assert.equal((await run({op:'preview',archive:foreign,passphrase:password})).status,400);
console.log('PASS: Master authorization, encrypted accounts/files/history, wrong password, tampering, preview without file writes, explicit confirmation, create-only file restore and project isolation.');
