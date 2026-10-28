import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const importTS=async(path)=>import('data:text/javascript;base64,'+Buffer.from(ts.transpile(readFileSync(new URL(path,import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022})).toString('base64'));
const {professionalAgendaPath,professionalPeriod,professionalSaveFields,newProfessionalId}=await importTS('../lib/professional-agenda.ts');
assert.match(newProfessionalId(),/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/);
assert.equal(professionalAgendaPath('cliente'),'/cliente/agendaprofissional');
assert.deepEqual(professionalPeriod('2028-02-20','Mês'),{from:'2028-02-01',to:'2028-02-29'});
assert.deepEqual(professionalPeriod('2026-12-29','Semana'),{from:'2026-12-29',to:'2027-01-04'});
const input={tenant_id:'fixture-tenant',professional_id:'fixture-professional',email:' STAFF@EXAMPLE.INVALID ',initial_password:'Fixture-staff-only-2026',confirm_password:'Fixture-staff-only-2026',role:'admin'};
const split=professionalSaveFields({id:input.professional_id,name:'Funcionário',active:true,create_access:true,access_email:input.email,initial_password:input.initial_password,confirm_password:input.confirm_password});
assert(!JSON.stringify(split.professional).includes(input.initial_password));assert.equal(split.access.email,'staff@example.invalid');
for(const changes of [{initial_password:'short'},{confirm_password:'mismatch'},{access_email:'bad'},{active:false}])assert.throws(()=>professionalSaveFields({id:'fixture',active:true,create_access:true,access_email:input.email,initial_password:input.initial_password,confirm_password:input.confirm_password,...changes}));
const {professionalAccessHandler}=await importTS('../supabase/functions/agenda-professional-access/handler.ts');
let mode='success';let calls=[];
const fetcher=async(url,options={})=>{const body=options.body?JSON.parse(options.body):null;calls.push({url,options,body});
 if(url.endsWith('/auth/v1/user'))return Response.json({id:'fixture-admin'},{status:mode==='expired'?401:200});
 if(url.endsWith('/agenda_professional_access')){assert(!JSON.stringify(body).includes(input.initial_password));assert(!('role' in body.p));if(mode==='forbidden')return Response.json({message:'Permissão de administrador necessária.'},{status:403});if(body.op==='prepare')return Response.json({complete:mode==='complete',user_id:['complete','resume'].includes(mode)?'fixture-user':null,slug:'fixture-tenant'});if(mode==='interrupted')throw new TypeError('Network failure');return Response.json({ok:true});}
 if(url.endsWith('/auth/v1/admin/users')){assert.equal(options.method,'POST');assert.equal(options.headers.Authorization,'Bearer fixture-secret');assert.equal(body.email_confirm,true);assert.equal(body.app_metadata.agenda_professional_id,input.professional_id);assert.equal(body.password,input.initial_password);return Response.json({id:'fixture-user'},{status:mode==='duplicate'?422:200});}throw Error('Unexpected endpoint');};
const handler=professionalAccessHandler({url:'https://fixture.example',serviceKey:'fixture-secret'},fetcher);
async function call(body=input,token=true){calls=[];return handler(new Request('https://fixture.example',{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer fixture-token'}:{})},body:JSON.stringify(body)}));}
assert.equal((await call(input,false)).status,401);mode='expired';assert.equal((await call()).status,401);mode='forbidden';assert.equal((await call()).status,400);assert(!calls.some(c=>c.url.endsWith('/admin/users')));
for(const test of ['success','resume','complete']){mode=test;const result=await call();assert.equal(result.status,200);const body=await result.json();assert(!JSON.stringify(body).includes(input.initial_password));assert.equal(body.email,'staff@example.invalid');assert.equal(calls.filter(c=>c.url.endsWith('/admin/users')).length,test==='success'?1:0);}
mode='duplicate';assert.equal((await call()).status,400);assert(!calls.some(c=>c.options.method==='PUT'||c.options.method==='DELETE'));
mode='interrupted';const failed=await call();assert.equal(failed.status,400);assert((await failed.json()).error.includes('mesmo e-mail'));
mode='success';for(const change of [{confirm_password:'wrong'},{initial_password:'short'},{email:'invalid'}]){assert.equal((await call({...input,...change})).status,400);assert(!calls.some(c=>c.url.endsWith('/admin/users')));}
console.log('PASS: professional URL and periods, credential isolation, password validation, live-session/admin gate, confirmed account creation, retry without resets, duplicate rejection and interruption recovery.');
