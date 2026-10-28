import {base64,unbase64,seal,unseal,digest,readBody,MAX_PLAIN} from './crypto.ts';
type Config={url:string;serviceKey:string};
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
const project='iktpbxfaygcvjkrajycy';
function pathURL(path:string){return path.split('/').map(encodeURIComponent).join('/');}
function validPath(p:unknown){return typeof p==='string'&&p.length<1024&&!p.startsWith('/')&&!p.split('/').some(s=>!s||s==='.'||s==='..')&&!/[\\\x00-\x1f]/.test(p);}
export function backupHandler(config:Config,fetcher:typeof fetch=fetch){return async(req:Request)=>{
 if(req.method!=='POST')return reply({error:'Método não permitido.'},405);
 const bearer=req.headers.get('authorization')||'';if(!/^Bearer [^\s]+$/.test(bearer))return reply({error:'Entre na conta Master.'},401);
 let safeError='';let fileWrites=false;
 try{
  const userHeaders={apikey:config.serviceKey,Authorization:bearer,'Content-Type':'application/json'};
  const user=await fetcher(config.url+'/auth/v1/user',{headers:userHeaders,signal:AbortSignal.timeout(10000)});if(!user.ok)return reply({error:'Sessão inválida.'},401);const actor=await user.json();
  const gate=await fetcher(config.url+'/rest/v1/rpc/agenda_recovery_access',{method:'POST',headers:userHeaders,body:'{}',signal:AbortSignal.timeout(10000)});if(!gate.ok||await gate.json()!==true)return reply({error:'Acesso exclusivo Master.'},403);
  const body=await readBody(req);if(!['export','preview','restore'].includes(body.op))throw Error('Operação inválida.');
  const admin={apikey:config.serviceKey,Authorization:'Bearer '+config.serviceKey,'Content-Type':'application/json'};
  async function rpc(op:string,p:unknown={}){const r=await fetcher(config.url+'/rest/v1/rpc/agenda_recovery_service',{method:'POST',headers:admin,body:JSON.stringify({op,actor:actor.id,p}),signal:AbortSignal.timeout(55000)});const d=await r.json();if(!r.ok){safeError='O banco recusou a operação. Nenhum cadastro foi substituído. Verifique conflitos de e-mail, telefone, vínculo ou horários e valide novamente.';throw Error(safeError);}return d;}
  const storageHeaders={apikey:config.serviceKey,Authorization:'Bearer '+config.serviceKey};
  async function download(path:string){return fetcher(config.url+'/storage/v1/object/authenticated/branding/'+pathURL(path),{headers:storageHeaders,signal:AbortSignal.timeout(20000)});}
  async function bytes(r:Response,max:number){const length=Number(r.headers.get('content-length')||0);if(length>max)throw Error('Arquivo excede o limite do backup.');const reader=r.body?.getReader();if(!reader)throw Error('Arquivo vazio.');const chunks:Uint8Array[]=[];let n=0;try{for(;;){const x=await reader.read();if(x.done)break;n+=x.value.length;if(n>max){await reader.cancel();throw Error('Arquivo excede o limite do backup.');}chunks.push(x.value);}}finally{reader.releaseLock();}const out=new Uint8Array(n);let at=0;for(const c of chunks){out.set(c,at);at+=c.length;}return out;}
  if(body.op==='export'){
   const data=await rpc('export');const files=[];let total=new TextEncoder().encode(JSON.stringify(data)).length;
   for(const obj of data.objects){if(obj.bucket!=='branding'||!validPath(obj.path))throw Error('Existe armazenamento não suportado. Nenhum backup parcial foi gerado.');const r=await download(obj.path);if(!r.ok)throw Error('Não foi possível copiar todos os arquivos. Tente novamente.');const content=await bytes(r,2097152);const encoded=base64(content);total+=encoded.length;if(total>MAX_PLAIN-4096)throw Error('O backup excede 12 MB. Nenhum arquivo parcial foi gerado.');files.push({bucket:'branding',path:obj.path,mime:obj.mime,data:encoded});}
   // Detect file replacement/deletion while binaries were being copied.
   const after=await rpc('export');if(await digest(after.objects)!==await digest(data.objects))throw Error('Os arquivos foram alterados durante a cópia. Gere o backup novamente.');
   const archive=await seal({project,data,files},body.passphrase);
   return reply({archive,summary:{exported_at:data.exported_at,customers:data.tables.customers.length,appointments:data.tables.appointments.length,accounts:data.accounts.length,files:files.length}});
  }
  const payload=await unseal(body.archive,body.passphrase);if(payload.project!==project||!payload.data||!Array.isArray(payload.files)||!Array.isArray(payload.data.objects))throw Error('Backup de outro projeto ou inválido.');
  const files=payload.files;if(files.length!==payload.data.objects.length||files.length>5000)throw Error('Lista de arquivos incompleta.');const seen=new Set<string>();
  for(const f of files){if(f.bucket!=='branding'||!validPath(f.path)||seen.has(f.path)||!payload.data.objects.some((o:any)=>o.bucket===f.bucket&&o.path===f.path)||!['image/png','image/jpeg'].includes(f.mime))throw Error('Arquivo de identidade visual inválido.');seen.add(f.path);const b=unbase64(f.data,2097152);if(!(f.mime==='image/png'?b[0]===137&&b[1]===80&&b[2]===78&&b[3]===71:b[0]===255&&b[1]===216&&b[2]===255))throw Error('Imagem inválida no backup.');}
  const archiveHash=await digest(body.archive);
  if(body.op==='preview'){const preview=await rpc('preview',{data:payload.data,archive_hash:archiveHash});return reply({...preview,files:files.length,exported_at:payload.data.exported_at});}
  if(body.confirmation!=='RESTAURAR'||typeof body.ticket!=='string')throw Error('Valide o arquivo e confirme a restauração.');
  await rpc('authorize',{archive_hash:archiveHash,ticket:body.ticket});
  // Files are restored first with create-only semantics. Never overwrite a current
  // image. A database failure can leave safe orphan files; retry completes them.
  for(const f of files){const existing=await download(f.path);if(existing.ok)continue;if(existing.status!==400&&existing.status!==404)throw Error('Não foi possível conferir os arquivos atuais.');const content=unbase64(f.data,2097152);const r=await fetcher(config.url+'/storage/v1/object/branding/'+pathURL(f.path),{method:'POST',headers:{...storageHeaders,'Content-Type':f.mime,'x-upsert':'false'},body:content as BodyInit,signal:AbortSignal.timeout(20000)});if(!r.ok)throw Error('Não foi possível recuperar um arquivo. Nenhum cadastro foi substituído. Valide e tente novamente.');fileWrites=true;}
  return reply({...await rpc('restore',{data:payload.data,archive_hash:archiveHash,ticket:body.ticket,confirmation:body.confirmation}),files:files.length});
 }catch(e){return reply({error:safeError||(e instanceof Error&&/^(Use uma senha|Arquivo|Formato|Senha do backup|Backup de outro|Lista de arquivos|Imagem inválida|Valide o arquivo|O backup excede|O conteúdo ultrapassa|Existe armazenamento|Não foi possível copiar|Não foi possível conferir|Não foi possível recuperar|Os arquivos foram alterados|Operação inválida)/.test(e.message)?e.message:'Não foi possível concluir o backup ou a restauração. Nenhum cadastro existente foi substituído.'),files_may_have_been_added:fileWrites},400);}
};}
