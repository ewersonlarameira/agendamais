import assert from 'node:assert/strict';
const origin=process.env.AGENDA_TEST_ORIGIN||'https://agenda-plus.ewersonlarameira.chatgpt.site';
async function call(path,body,requestOrigin=origin){const r=await fetch(origin+path,{method:body?'POST':'GET',redirect:'manual',headers:body?{'Content-Type':'application/json',Origin:requestOrigin}:{},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(20000)});return {r,text:await r.text()};}
for(const path of ['/','/demo','/master','/barbeariamagalhaes','/barbeariamagalhaes/admin','/privacidade','/termos']){const {r,text}=await call(path);assert.equal(r.status,200,path);assert(!text.includes('<title>Sign in required</title>'));console.log('PASS public page '+path);}
const tests=[
 ['/api/auth',null,d=>d.isOwner===false&&d.setupRequired===false,'Anonymous request has no owner identity'],
 ['/api/rpc',{op:'session'},d=>!!d.error,'Session requires login'],
 ['/api/rpc',{op:'master_data'},d=>!!d.error,'Master data requires login'],
 ['/api/rpc',{op:'workspace',p:{tenant_id:'00000000-0000-0000-0000-000000000001'}},d=>!!d.error,'Workspace requires login'],
 ['/api/rpc',{op:'finance_get',p:{tenant_id:'00000000-0000-0000-0000-000000000001',from:'2026-10-01',to:'2026-10-31'}},d=>!!d.error,'Finance requires login'],
 ['/api/push',{op:'status',p:{tenant_id:'00000000-0000-0000-0000-000000000001'}},d=>!!d.error,'Device settings require login'],
 ['/api/rpc',{op:'backup_export'},d=>!!d.error,'Business export requires Master login'],
 ['/api/rpc',{op:'setup_state'},d=>!!d.error,'Internal setup is not a public operation'],
 ['/api/auth',{action:'setup',password:'fixture-only-123',confirmPassword:'fixture-only-123'},d=>!!d.error,'Anonymous caller cannot bootstrap Master'],
 ['/api/auth',{action:'signup',email:'fixture@example.invalid',password:'fixture-only-123',confirmPassword:'mismatch'},d=>String(d.error).includes('coincidem'),'Mismatched password rejected before creating account']
];
for(const [path,body,check,label] of tests){const {r,text}=await call(path,body);assert(r.headers.get('content-type')?.includes('application/json'),label);const d=JSON.parse(text);assert(check(d),label);assert.equal(r.status,body?400:200,label);console.log('PASS '+label);}
const cross=await call('/api/auth',{action:'reset',email:'fixture@example.invalid'},'https://untrusted.example');assert.equal(cross.r.status,400);assert(String(JSON.parse(cross.text).error).includes('Origem'));console.log('PASS cross-origin mutation rejected before sending email');
const {r,text}=await call('/api/rpc',{op:'catalog',p:{slug:'barbeariamagalhaes'}});assert.equal(r.status,200);const catalog=JSON.parse(text);for(const key of ['customers','appointments','memberships','financial_entries','document_number'])assert(!(key in catalog));assert(!('document_number' in catalog.tenant));console.log('PASS public catalog excludes customer, finance, member and tax data');
