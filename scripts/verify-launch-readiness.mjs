import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
function url(path,replacements={}){let s=readFileSync(new URL(path,import.meta.url),'utf8');for(const [a,b] of Object.entries(replacements))s=s.replace(a,b);return 'data:text/javascript;base64,'+Buffer.from(ts.transpile(s,{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022})).toString('base64');}
const {readAuthInput}=await import(url('../lib/auth-input.ts'));
const {tenantManifestPath}=await import(url('../lib/install-identity.ts'));
const whatsapp=url('../lib/whatsapp.ts');
const {passwordSupportMessage,passwordSupportUrl,passwordSupportPhone}=await import(url('../lib/password-support.ts',{"from './whatsapp'":"from '"+whatsapp+"'"}));
assert.equal(passwordSupportPhone,'5524999074698');
const link=new URL(passwordSupportUrl('client@example.invalid','/barbearia/admin','https://agenda.example'));
assert(link.href.includes(passwordSupportPhone));const message=link.searchParams.get('text');
assert(message.includes('client@example.invalid'));assert(message.includes('/barbearia'));assert(message.includes('https://agenda.example/barbearia/admin'));
assert(!passwordSupportMessage('','/barbearia/admin?access_token=private#private','https://agenda.example').includes('private'));
assert(passwordSupportMessage('','/master').includes('Administrador Master'));
for(const path of ['/barbearia','/barbearia/admin'])assert.equal(tenantManifestPath(path),'/api/manifest?tenant=barbearia');
for(const path of ['/','/master','/demo','/privacidade','/api/auth','/bad%2Fslug/admin'])assert.equal(tenantManifestPath(path),'/api/manifest');
const request=p=>new Request('https://agenda.example/api/auth',{method:'POST',body:JSON.stringify(p)});
assert.equal((await readAuthInput(request({action:'login',email:' OWNER@EXAMPLE.INVALID ',password:'some-password'}))).email,'owner@example.invalid');
for(const p of [{action:'unknown'},{action:'password'},{action:'login',email:'bad',password:'some-password'},{action:'recovery',access_token:'x'},{action:'signup',email:'x@example.invalid',password:'short'},{action:'password',password:'á'.repeat(37)}])await assert.rejects(()=>readAuthInput(request(p)));
await assert.rejects(()=>readAuthInput(new Request('https://agenda.example',{method:'POST',body:'{"password":"sensitive'})),error=>!error.message.includes('sensitive'));
await assert.rejects(()=>readAuthInput(request({action:'login',email:'x@example.invalid',password:'a'.repeat(25000)})),/grande/);
const handlers={};const self={addEventListener:(name,fn)=>handlers[name]=fn};vm.runInNewContext(readFileSync(new URL('../public/sw.js',import.meta.url),'utf8'),{self,URL,location:{origin:'https://agenda.example'}});
for(const path of ['/api/auth','/api/rpc','/master','/barbearia/admin','/barbearia']){let intercepted=false;handlers.fetch({request:{url:'https://agenda.example'+path,method:'GET'},respondWith:()=>{intercepted=true}});assert(!intercepted,'private/dynamic response must not enter service-worker cache');}
console.log('PASS: support WhatsApp number/context without tokens or passwords, tenant admin/public manifest identity, auth input validation/body limits and exclusion of dynamic/private pages from offline cache. No support message sent.');
