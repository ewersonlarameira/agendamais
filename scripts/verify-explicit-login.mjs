import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';
const state={mode:'ok',deleted:[],calls:[]};globalThis.__agendaLoginFixture=state;
const moduleURL=s=>'data:text/javascript;base64,'+Buffer.from(s).toString('base64');
const headers=moduleURL(`export async function cookies(){return {get:name=>({value:name==='agenda_access'?'fixture-access':'fixture-refresh'}),delete:name=>globalThis.__agendaLoginFixture.deleted.push(name)}}`);
const agenda=moduleURL(`export const SB='https://fixture.example',KEY='fixture-key';export function guard(){}export function failure(e){return Response.json({error:e.message},{status:400})}export async function rpc(){}export async function rpcNamed(){if(globalThis.__agendaLoginFixture.mode==='push-failure')throw Error('push unavailable');return {}}`);
const input=moduleURL(ts.transpile(readFileSync(new URL('../lib/auth-input.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}));
let source=readFileSync(new URL('../app/api/auth/route.ts',import.meta.url),'utf8').replace("'next/headers'",JSON.stringify(headers)).replace("'../../../lib/agenda'",JSON.stringify(agenda)).replace("'../../../lib/auth-input'",JSON.stringify(input)).replace("'../../../lib/login-attempt'",JSON.stringify(moduleURL(ts.transpile(readFileSync(new URL('../lib/login-attempt.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022})))).replace("'../../chatgpt-auth'",JSON.stringify(moduleURL('export async function getChatGPTUser(){return null}')));
const {POST}=await import(moduleURL(ts.transpile(source,{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022})));
const originalFetch=globalThis.fetch;
globalThis.fetch=async(url,options={})=>{state.calls.push(url);if(url.includes('/logout'))return Response.json({}, {status:state.mode==='revoke-failure'?503:200});if(url.includes('refresh_token'))throw Error('expired refresh');if(url.includes('grant_type=password'))return Response.json({access_token:'fixture-new',refresh_token:'fixture-new-refresh',expires_in:3600});throw Error('Unexpected endpoint');};
const request=action=>new Request('https://fixture.example/api/auth',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action})});
try{
 for(const mode of ['ok','push-failure','revoke-failure']){state.mode=mode;state.calls=[];state.deleted=[];const r=await POST(request('logout'));assert.equal(r.status,mode==='ok'?200:400);assert.deepEqual(state.deleted,['agenda_access','agenda_refresh'],'logout must always remove both cookies');}
 state.mode='ok';state.calls=[];state.deleted=[];const r=await POST(request('refresh'));assert.equal(r.status,400);assert((await r.json()).error.includes('senha'));assert.equal(state.calls.length,0,'saved refresh credential cannot establish a session');
 for(const payload of [{action:'login',email:'fixture@example.invalid',password:''},{action:'login',email:'bad',password:'fixture'}]){const r=await POST(new Request('https://fixture.example/api/auth',{method:'POST',body:JSON.stringify(payload)}));assert.equal(r.status,400);assert.equal(state.calls.length,0);}
 console.log('PASS: logout clears access and refresh cookies on success, push failure and Auth failure; refresh cannot enter; incomplete credentials are rejected before authentication.');
}finally{globalThis.fetch=originalFetch;delete globalThis.__agendaLoginFixture;}
