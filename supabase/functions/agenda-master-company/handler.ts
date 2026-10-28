type Config={url:string;serviceKey:string};
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
export function masterCompanyCredentialsHandler(config:Config,fetcher:typeof fetch=fetch){return async(req:Request)=>{
 if(req.method!=='POST')return reply({error:'Método não permitido.'},405);
 const bearer=req.headers.get('authorization')||'';if(!/^Bearer [^\s]+$/.test(bearer))return reply({error:'Entre na conta Master.'},401);
 let changed=false;let safeError='';
 try{
  const headers={apikey:config.serviceKey,Authorization:bearer,'Content-Type':'application/json'};
  const check=await fetcher(config.url+'/auth/v1/user',{headers,signal:AbortSignal.timeout(10000)});
  if(!check.ok)return reply({error:'Sessão inválida.'},401);
  const actor=await check.json();if(!actor.id)return reply({error:'Sessão inválida.'},401);
  const raw=await req.text();if(raw.length>12000)return reply({error:'Formulário muito grande.'},400);
  const body=JSON.parse(raw);const password=body.new_password;
  if(password!==undefined&&password!==''){
   if(typeof password!=='string'||password.length<10||new TextEncoder().encode(password).length>72)return reply({error:'Use uma senha com pelo menos 10 caracteres e até 72 bytes.'},400);
   if(password!==body.confirm_password)return reply({error:'As senhas não coincidem.'},400);
  }
  const p:Record<string,unknown>={tenant_id:body.tenant_id,id:body.id,revision:body.revision,email:String(body.email||'').trim().toLowerCase()};
  async function rpc(op:string){const r=await fetcher(config.url+'/rest/v1/rpc/agenda_master_company',{method:'POST',headers,body:JSON.stringify({op,p}),signal:AbortSignal.timeout(15000)});const d=await r.json();if(!r.ok){safeError=d.message||'Não foi possível editar o acesso.';throw new Error(safeError);}return d;}
  const prepared=await rpc('credentials_prepare');p.revision=prepared.revision;
  const adminHeaders={...headers,Authorization:'Bearer '+config.serviceKey};
  let accountId=prepared.user_id;
  if(!accountId&&!password)return reply({error:'Defina uma senha inicial para criar a conta deste acesso.'},400);
  const values:Record<string,unknown>={email:p.email,email_confirm:true};if(password)values.password=password;
  if(!accountId)values.app_metadata={agenda_member_actor:actor.id,agenda_member_id:p.id,agenda_member_tenant:p.tenant_id};
  const updated=await fetcher(config.url+'/auth/v1/admin/users'+(accountId?'/'+accountId:''),{method:accountId?'PUT':'POST',headers:adminHeaders,body:JSON.stringify(values),signal:AbortSignal.timeout(15000)});
  if(!updated.ok)return reply({error:'O serviço de autenticação não aceitou a alteração. Confira o e-mail e as regras de senha. Atualize o editor antes de tentar novamente.'},400);
  changed=true;const account=await updated.json();accountId=account.user?.id||account.id;if(!accountId)throw new Error('Não foi possível confirmar a conta.');
  p.account_id=accountId;await rpc('credentials_finish');
  return reply({ok:true,email:p.email});
 }catch(error){return reply({error:changed?'A autenticação foi atualizada, mas o vínculo não foi confirmado nesta resposta. Atualize o editor e repita com o mesmo e-mail para concluir.':safeError||'Não foi possível confirmar a alteração. Atualize o editor antes de repetir.'},400);}
};}
