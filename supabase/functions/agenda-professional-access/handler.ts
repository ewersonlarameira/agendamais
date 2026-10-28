type Config={url:string;serviceKey:string};
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});
export function professionalAccessHandler(config:Config,fetcher:typeof fetch=fetch){return async(req:Request)=>{
 if(req.method!=='POST')return reply({error:'Método não permitido.'},405);
 const bearer=req.headers.get('authorization')||'';if(!/^Bearer [^\s]+$/.test(bearer))return reply({error:'Entre na conta do administrador.'},401);
 let safeError='';let stage='auth';
 try{
  const headers={apikey:config.serviceKey,Authorization:bearer,'Content-Type':'application/json'};
  const check=await fetcher(config.url+'/auth/v1/user',{headers,signal:AbortSignal.timeout(10000)});if(!check.ok)return reply({error:'Sessão inválida. Entre novamente.'},401);const actor=await check.json();if(!actor.id)return reply({error:'Sessão inválida.'},401);
  const raw=await req.text();if(raw.length>12000)return reply({error:'Formulário muito grande.'},400);const body=JSON.parse(raw);
  const email=String(body.email||'').trim().toLowerCase();
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254)return reply({error:'Informe um e-mail válido.'},400);
  if(typeof body.initial_password!=='string'||body.initial_password.length<10||new TextEncoder().encode(body.initial_password).length>72)return reply({error:'Use uma senha inicial com pelo menos 10 caracteres e até 72 bytes.'},400);
  if(body.initial_password!==body.confirm_password)return reply({error:'As senhas não coincidem.'},400);
  const p:Record<string,unknown>={tenant_id:body.tenant_id,professional_id:body.professional_id,email};
  async function rpc(op:string){const r=await fetcher(config.url+'/rest/v1/rpc/agenda_professional_access',{method:'POST',headers,body:JSON.stringify({op,p}),signal:AbortSignal.timeout(15000)});const d=await r.json();if(!r.ok){safeError=d.message||'Não foi possível criar o acesso profissional.';throw Error(safeError);}return d;}
  stage='prepare';const prepared=await rpc('prepare');let accountId=prepared.user_id;
  if(!prepared.complete){
   if(!accountId){
    stage='create';const r=await fetcher(config.url+'/auth/v1/admin/users',{method:'POST',headers:{...headers,Authorization:'Bearer '+config.serviceKey},body:JSON.stringify({email,password:body.initial_password,email_confirm:true,app_metadata:{agenda_professional_actor:actor.id,agenda_professional_id:p.professional_id,agenda_professional_tenant:p.tenant_id}}),signal:AbortSignal.timeout(15000)});
    if(!r.ok)return reply({error:'O acesso não foi criado nesta resposta. O e-mail pode estar em uso ou a senha não atender às regras. Nenhuma senha existente foi alterada. Repita com o mesmo profissional e e-mail.'},400);
    const account=await r.json();accountId=account.user?.id||account.id;if(!accountId)throw Error('Conta não confirmada.');
   }
   stage='finish';p.account_id=accountId;await rpc('finish');
  }
  return reply({ok:true,email,slug:prepared.slug,reused_access:!!prepared.user_id});
 }catch{return reply({error:safeError||(stage==='auth'?'Não foi possível validar a sessão.':'Não foi possível confirmar o acesso. O profissional foi preservado. Repita com o mesmo e-mail e mantenha a senha da primeira tentativa.')},400);}
};}
