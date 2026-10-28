import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const js=ts.transpile(readFileSync(new URL('../supabase/functions/agenda-master-company/handler.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022});
const {masterCompanyCredentialsHandler}=await import('data:text/javascript;base64,'+Buffer.from(js).toString('base64'));
const calls=[];let mode='existing';
const input={tenant_id:'tenant-fixture',id:'member-fixture',revision:'original-revision',email:' NEW@EXAMPLE.INVALID ',new_password:'Fixture-Password-2026',confirm_password:'Fixture-Password-2026'};
const reply=(value,status=200)=>Response.json(value,{status});
async function fetcher(url,options){const body=options.body?JSON.parse(options.body):null;calls.push({url,options,body});
 if(url.endsWith('/auth/v1/user'))return mode==='expired'?reply({},401):reply({id:'master-fixture'});
 if(url.endsWith('/rpc/agenda_master_company')){
  assert(!JSON.stringify(body).includes(input.new_password));assert(!('confirm_password' in body.p));assert(!('new_password' in body.p));
  if(mode==='forbidden')return reply({message:'Acesso exclusivo Master.'},403);
  if(body.op==='credentials_prepare')return reply({user_id:mode==='new'?'': 'client-fixture',revision:'bound-revision'});
  assert.equal(body.p.account_id,'client-fixture');assert.equal(body.p.revision,'bound-revision');
  if(mode==='interrupted')throw new TypeError('Connection interrupted');return reply({ok:true});
 }
 if(url.includes('/auth/v1/admin/users')){
  assert.equal(options.headers.Authorization,'Bearer fixture-service');assert.equal(body.email,'new@example.invalid');assert.equal(body.email_confirm,true);
  assert.equal(options.method,mode==='new'?'POST':'PUT');
  if(mode==='new'){assert.equal(body.app_metadata.agenda_member_id,'member-fixture');assert.equal(body.app_metadata.agenda_member_actor,'master-fixture');}
  if(mode==='email-only')assert(!('password' in body));else assert.equal(body.password,input.new_password);
  return mode==='auth-rejected'?reply({},422):reply({id:'client-fixture'});
 }
 throw new Error('Unexpected endpoint');
}
const handler=masterCompanyCredentialsHandler({url:'https://fixture.example.invalid',serviceKey:'fixture-service'},fetcher);
async function run(body=input,authenticated=true){calls.length=0;return handler(new Request('https://edge.example.invalid',{method:'POST',headers:authenticated?{Authorization:'Bearer fixture-master-token'}:{},body:JSON.stringify(body)}));}
let response=await run(input,false);assert.equal(response.status,401);assert.equal(calls.length,0);
mode='expired';response=await run();assert.equal(response.status,401);assert.equal(calls.length,1);
mode='forbidden';response=await run();assert.equal(response.status,400);assert(!calls.some(c=>c.url.includes('/admin/users')));
mode='existing';response=await run({...input,confirm_password:'different'});assert.equal(response.status,400);assert.equal(calls.length,1);
for(const scenario of ['existing','new','email-only']){mode=scenario;response=await run(scenario==='email-only'?{...input,new_password:'',confirm_password:''}:input);assert.equal(response.status,200);assert.deepEqual(await response.json(),{ok:true,email:'new@example.invalid'});assert.equal(calls.length,4);}
mode='auth-rejected';response=await run();assert.equal(response.status,400);assert(!calls.some(c=>c.body?.op==='credentials_finish'));
mode='interrupted';response=await run();assert.equal(response.status,400);assert((await response.json()).error.includes('autenticação foi atualizada'));assert(!calls.some(c=>c.options.method==='DELETE'));
const malformed=await handler(new Request('https://edge.example.invalid',{method:'POST',headers:{Authorization:'Bearer fixture-master-token'},body:'{"new_password":"private-fixture"'}));assert.equal(malformed.status,400);assert(!JSON.stringify(await malformed.json()).includes('private-fixture'));
console.log('PASS: verified Auth session, database Master gate before Auth administration, email/password updates, initial-account creation, SQL password exclusion, bound revision, Auth rejection, partial-failure recovery and secret-free responses. Auth operations are mocked.');
