type Config={url:string;serviceKey:string};
type Fetcher=typeof fetch;
const fields=['name','responsible','email','phone','slug','document_type','document_number','plan_id','starts_on','expires_on','amount','paid'] as const;
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
export function companyAccessHandler(config:Config,fetcher:Fetcher=fetch){
 return async(req:Request)=>{
  if(req.method!=='POST')return reply({error:'Método não permitido.'},405);
  const bearer=req.headers.get('authorization')||'';
  if(!/^Bearer [^\s]+$/.test(bearer))return reply({error:'Entre na sua conta Master.'},401);
  if(!config.url||!config.serviceKey)return reply({error:'Serviço de criação de acesso indisponível.'},503);
  const headers={apikey:config.serviceKey,Authorization:bearer,'Content-Type':'application/json'};
  let stage='authentication';
  try{
   // Verify the live user with Auth, then authorize the Master in PostgreSQL.
   const userResponse=await fetcher(config.url+'/auth/v1/user',{headers,signal:AbortSignal.timeout(10000)});
   if(!userResponse.ok)return reply({error:'Sessão inválida. Entre novamente.'},401);
   const user=await userResponse.json();
   if(!user.id)return reply({error:'Sessão inválida.'},401);
   const raw=await req.text();if(raw.length>20000)return reply({error:'Formulário muito grande.'},400);
   const body=JSON.parse(raw);const email=String(body.email||'').trim().toLowerCase();
   if(typeof body.initial_password!=='string'||body.initial_password.length<10||new TextEncoder().encode(body.initial_password).length>72)return reply({error:'Use uma senha inicial com pelo menos 10 caracteres e até 72 bytes.'},400);
   if(body.initial_password!==body.confirm_password)return reply({error:'As senhas não coincidem.'},400);
   if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(body.request_id||''))return reply({error:'Reabra o cadastro e tente novamente.'},400);
   // Strict allowlist keeps passwords out of SQL, audit records and business backups.
   const p:Record<string,unknown>={};for(const key of fields)if(body[key]!==undefined)p[key]=body[key];p.email=email;
   async function rpc(op:string,requestId:string){
    const r=await fetcher(config.url+'/rest/v1/rpc/agenda_company_access',{method:'POST',headers,body:JSON.stringify({op,p,request_id:requestId}),signal:AbortSignal.timeout(15000)});
    const d=await r.json();if(!r.ok)throw new Error(d.message||'Não foi possível cadastrar a empresa.');return d;
   }
   stage='prepare';const prepared=await rpc('prepare',body.request_id);
   let reused=!!prepared.user_id;
   if(!prepared.complete){
    if(!prepared.user_id){
     stage='account';
     const created=await fetcher(config.url+'/auth/v1/admin/users',{method:'POST',headers:{...headers,Authorization:'Bearer '+config.serviceKey},body:JSON.stringify({email,password:body.initial_password,email_confirm:true,app_metadata:{agenda_company_actor:user.id,agenda_company_slug:p.slug,agenda_company_request:prepared.request_id}}),signal:AbortSignal.timeout(15000)});
     if(!created.ok)return reply({error:'Não foi possível criar o acesso. O e-mail pode já estar em uso ou a senha pode não atender às regras. Nenhuma senha existente foi alterada. Se houve interrupção, tente novamente com o mesmo e-mail e link.'},400);
     const account=await created.json();if(!(account.user?.id||account.id))throw new Error('Não foi possível confirmar a criação do acesso.');
    }
    stage='finish';await rpc('finish',prepared.request_id);
   }
   return reply({ok:true,email,slug:p.slug,reused_access:reused});
  }catch(error){
   // A timeout may occur after Auth or PostgreSQL committed. Preserve the account:
   // server-owned request metadata allows a retry without resetting credentials.
   if(stage==='prepare'&&error instanceof Error&&error.name!=='TimeoutError'&&error.name!=='TypeError')return reply({error:error.message},400);
   return reply({error:stage==='authentication'?'Não foi possível validar a sessão. Tente novamente.':'O cadastro não foi concluído nesta resposta. Tente novamente com o mesmo e-mail e link. Se o acesso já foi criado, mantenha a senha da primeira tentativa.'},503);
  }
 };
}
