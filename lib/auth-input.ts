const actions=new Set(['login','refresh','logout','password','reset','signup','setup','recovery']);
export async function readAuthInput(req:Request){
 const reader=req.body?.getReader();if(!reader)throw new Error('Solicitação inválida.');
 const chunks:Uint8Array[]=[];let size=0;
 try{while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>20000){await reader.cancel();throw new Error('Solicitação muito grande.');}chunks.push(next.value);}}finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const part of chunks){bytes.set(part,offset);offset+=part.length;}
 let p:any;try{p=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{throw new Error('Solicitação inválida.');}
 if(!p||typeof p!=='object'||Array.isArray(p)||!actions.has(p.action))throw new Error('Operação de autenticação inválida.');
 if(['login','reset','signup'].includes(p.action)){
  if(typeof p.email!=='string'||p.email.length>254||! /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(p.email.trim()))throw new Error('Informe um e-mail válido.');p.email=p.email.trim().toLowerCase();
 }
 if(['signup','setup','password'].includes(p.action)){
  if(typeof p.password!=='string'||p.password.length<10||new TextEncoder().encode(p.password).length>72)throw new Error('Use uma senha com pelo menos 10 caracteres e até 72 bytes.');
 }
 if(p.action==='login'&&(typeof p.password!=='string'||!p.password||p.password.length>1024))throw new Error('Informe sua senha.');
 if(p.action==='recovery'&&([p.access_token,p.refresh_token].some(value=>typeof value!=='string'||!value||value.length>8192)))throw new Error('Link inválido ou expirado.');
 return p;
}
