import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const source=readFileSync(new URL('../supabase/functions/agenda-company-access/handler.ts',import.meta.url),'utf8');
const js=ts.transpile(source,{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022});
const {companyAccessHandler}=await import('data:text/javascript;base64,'+Buffer.from(js).toString('base64'));
const requestId='12345678-1234-4234-8234-123456789abc';
const input={name:'Fixture',responsible:'Fixture',email:' ADMIN@EXAMPLE.INVALID ',slug:'fixture-access',document_type:'CPF',document_number:'52998224725',plan_id:requestId,starts_on:'2026-10-27',expires_on:'2026-11-27',amount:49.90,initial_password:'Fixture-only-2026',confirm_password:'Fixture-only-2026',request_id:requestId};
const config={url:'https://project.example.invalid',serviceKey:'fixture-service-key'};
const response=(data,status=200)=>Response.json(data,{status});
const calls=[];let mode='success';
async function fakeFetch(url,options){
 const body=options.body?JSON.parse(options.body):null;calls.push({url,options,body});
 if(url.endsWith('/auth/v1/user'))return mode==='expired'?response({},401):response({id:'master-fixture'});
 if(url.endsWith('/rpc/agenda_company_access')){
  assert(!JSON.stringify(body).includes(input.initial_password),'password reached SQL');
  for(const key of ['password','initial_password','confirm_password','request_id','arbitrary'])assert(!(key in body.p));
  if(mode==='forbidden')return response({message:'Acesso exclusivo Master.'},403);
  if(body.op==='prepare')return response({complete:mode==='complete',user_id:['resume','complete'].includes(mode)?'client-fixture':null,request_id:requestId});
  if(mode==='interrupted')throw new TypeError('Network interruption');
  return response({ok:true,complete:true,tenant_id:'tenant-fixture'});
 }
 if(url.endsWith('/auth/v1/admin/users')){
  assert.equal(options.headers.Authorization,'Bearer '+config.serviceKey);
  assert.equal(body.email_confirm,true);assert.equal(body.password,input.initial_password);
  assert.equal(body.app_metadata.agenda_company_actor,'master-fixture');assert.equal(body.app_metadata.agenda_company_slug,input.slug);
  assert.equal(body.app_metadata.agenda_company_request,requestId);
  return mode==='duplicate'?response({},422):response({id:'client-fixture'});
 }
 throw Error('Unexpected endpoint');
}
const handler=companyAccessHandler(config,fakeFetch);
async function run(body=input,authorized=true){calls.length=0;return handler(new Request('https://edge.example.invalid',{method:'POST',headers:authorized?{Authorization:'Bearer fixture-user-token'}:{},body:JSON.stringify({...body,arbitrary:'ignored'})}));}
let r=await run(input,false);assert.equal(r.status,401);assert.equal(calls.length,0);
mode='expired';r=await run();assert.equal(r.status,401);assert.equal(calls.length,1);
mode='forbidden';r=await run();assert.equal(r.status,400);assert(!calls.some(c=>c.url.endsWith('/admin/users')));
mode='success';r=await run({...input,confirm_password:'different'});assert.equal(r.status,400);assert.equal(calls.length,1);
r=await run({...input,initial_password:'a'.repeat(73),confirm_password:'a'.repeat(73)});assert.equal(r.status,400);
r=await run();assert.equal(r.status,200);let result=await r.json();assert.equal(result.email,'admin@example.invalid');assert.equal(result.reused_access,false);assert(!JSON.stringify(result).includes(input.initial_password));assert.equal(calls.length,4);
assert.equal(calls[1].options.headers.Authorization,'Bearer fixture-user-token');assert.equal(calls[3].options.headers.Authorization,'Bearer fixture-user-token');
mode='duplicate';r=await run();assert.equal(r.status,400);assert(!calls.some(c=>c.body?.op==='finish'));assert(!calls.some(c=>c.options.method==='PUT'||c.options.method==='DELETE'));
for(const retry of ['resume','complete']){mode=retry;r=await run();assert.equal(r.status,200);result=await r.json();assert.equal(result.reused_access,true);assert(!calls.some(c=>c.url.endsWith('/admin/users')));}
mode='interrupted';r=await run();assert.equal(r.status,503);assert(!calls.some(c=>c.options.method==='DELETE'),'ambiguous commit must not delete account');
const ui=readFileSync(new URL('../app/ui.tsx',import.meta.url),'utf8');assert(!/signInWithOAuth|accounts\.google|Continuar com Google|Entrar com Google/.test(ui));
console.log('PASS: live Auth verification, Master gate, password validation, SQL credential exclusion, confirmed account provisioning, retry recovery, duplicate protection, no password response, no session replacement and no Google login');
