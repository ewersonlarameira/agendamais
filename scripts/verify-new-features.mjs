import assert from 'node:assert/strict';
import {validDocument,formatDocument} from '../lib/documents.ts';
import {defaultTemplates,fillTemplate,messageValues,whatsappUrl} from '../lib/whatsapp.ts';
assert(validDocument('CPF','529.982.247-25'));assert(!validDocument('CPF','11111111111'));assert(!validDocument('CPF','52998224724'));
assert(validDocument('CNPJ','00.000.000/E08G-12'));assert(validDocument('CNPJ','11.222.333/0001-81'));assert(!validDocument('CNPJ','00.000.000/E08G-13'));assert(!validDocument('CNPJ','00000000000000'));
assert.equal(formatDocument('CPF','52998224725'),'529.982.247-25');assert.equal(formatDocument('CNPJ','00000000E08G12'),'00.000.000/E08G-12');
const data={tenant:{name:'Empresa teste'},settings:{},customers:[{id:'c',name:'Cliente de teste'}],services:[{id:'s',name:'Corte'}],professionals:[{id:'p',name:'Profissional'}]};
const a={customer_id:'c',service_id:'s',professional_id:'p',starts_at:'2026-10-28T13:30:00Z',price:35.5,payment_method:'Pix',protocol:'TESTE'};
for(const template of Object.values(defaultTemplates)){const message=fillTemplate(template,messageValues(data,a));assert(!/\{[a-z_]+\}/.test(message));for(const text of ['Cliente de teste','28/10/2026','10:30','Corte','35,50','Pix'])assert(message.includes(text));const url=whatsappUrl('24999999999',message);assert.equal(new URL(url).searchParams.get('text'),message);assert(url.startsWith('https://wa.me/5524999999999?'));}
assert.equal(whatsappUrl('', 'teste'),'');assert.equal(messageValues(data,{...a,payment_method:null}).forma_pagamento,'A combinar');
console.log('PASS documents, masks, all WhatsApp placeholders, São Paulo time, payment and emoji URL round-trip');
