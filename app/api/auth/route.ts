import {cookies} from 'next/headers';
import {SB,KEY,guard,failure,rpc,rpcNamed} from '../../../lib/agenda';
import {guardedLogin,LoginFailure} from '../../../lib/login-attempt';
import {readAuthInput} from '../../../lib/auth-input';
import {getChatGPTUser} from '../../chatgpt-auth';
async function auth(path:string,body:any,token?:string){const r=await fetch(SB+'/auth/v1/'+path,{method:path==='user'?'PUT':'POST',headers:{apikey:KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});const d:any=await r.json();if(!r.ok)throw Object.assign(new Error(d.msg||d.message||d.error_description||'Não foi possível autenticar.'),{authCode:d.code,status:r.status});return d;}
async function loginControl(op:string,fields:Record<string,unknown>){const r=await fetch(SB+'/rest/v1/rpc/agenda_login_attempt',{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({op,p:{...fields,secret:process.env.AGENDA_GATEWAY_SECRET}}),cache:'no-store',signal:AbortSignal.timeout(15000)});const d:any=await r.json();if(!r.ok)throw new LoginFailure('Não foi possível conferir a proteção de acesso. Tente novamente.',503);return d;}
export async function POST(req:Request){try{guard(req);const p:any=await readAuthInput(req);const c=await cookies();let d:any;const origin=new URL(req.url).origin;const returnTo=typeof p.returnTo==='string'&&/^\/(?!\/)/.test(p.returnTo)?p.returnTo:'/master';const token=c.get('agenda_access')?.value;
if(p.action==='logout'){
 try{
 let logoutToken=token;const refresh=c.get('agenda_refresh')?.value;
 if(!logoutToken&&refresh)logoutToken=(await auth('token?grant_type=refresh_token',{refresh_token:refresh})).access_token;
 if(logoutToken){
  try{await rpcNamed('agenda_push_client',{op:'logout',p:{}},logoutToken)}catch{
   if(!refresh)throw new Error('Entre novamente para encerrar os avisos com segurança.');
   logoutToken=(await auth('token?grant_type=refresh_token',{refresh_token:refresh})).access_token;
   await rpcNamed('agenda_push_client',{op:'logout',p:{}},logoutToken);
  }
  const signedOut=await fetch(SB+'/auth/v1/logout?scope=global',{method:'POST',headers:{apikey:KEY,Authorization:'Bearer '+logoutToken}});
  if(!signedOut.ok)throw new Error('Não foi possível encerrar as sessões. Tente novamente.');
 }
 return Response.json({ok:true});
 }finally{c.delete('agenda_access');c.delete('agenda_refresh');}
}
if(p.action==='reset'){await auth('recover?redirect_to='+encodeURIComponent(origin+returnTo),{email:p.email});return Response.json({message:'Se o e-mail estiver cadastrado, você receberá as instruções.'});}
if(p.action==='password'){if(!token)throw new Error('Entre na sua conta.');if(p.password.length<10)throw new Error('Use pelo menos 10 caracteres.');await auth('user',{password:p.password},token);return Response.json({message:'Senha atualizada.'});}
if(p.action==='refresh')throw new Error('Informe seu e-mail e sua senha para entrar.');
else if(p.action==='recovery'){const r=await fetch(SB+'/auth/v1/user',{headers:{apikey:KEY,Authorization:'Bearer '+p.access_token}});if(!r.ok)throw new Error('Link inválido ou expirado.');d={access_token:p.access_token,refresh_token:p.refresh_token,expires_in:3600};}
else if(p.action==='signup'||p.action==='setup'){
if(typeof p.password!=='string'||p.password.length<10)throw new Error('Use pelo menos 10 caracteres.');
if(p.password!==p.confirmPassword)throw new Error('As senhas não coincidem.');
let email=p.email;
if(p.action==='setup'){const owner=await getChatGPTUser();if(!owner||!process.env.AGENDA_OWNER_EMAIL||owner.email.toLowerCase()!==process.env.AGENDA_OWNER_EMAIL.toLowerCase())throw new Error('A configuração inicial exige o proprietário conectado ao Site.');const state=await rpc('setup_state',{secret:process.env.AGENDA_GATEWAY_SECRET});if(state.configured)throw new Error('O acesso Master já está configurado. Use Entrar ou recuperar senha.');email=owner.email;}
if(p.action==='setup'){try{d=await auth('token?grant_type=password',{email,password:p.password})}catch{d=await auth('signup?redirect_to='+encodeURIComponent(origin+returnTo),{email,password:p.password})}}else d=await auth('signup?redirect_to='+encodeURIComponent(origin+returnTo),{email,password:p.password});
if(p.action==='setup'){if(!d.user?.id)throw new Error('Confira seu e-mail para confirmar a conta.');await rpc('bootstrap',{secret:process.env.AGENDA_GATEWAY_SECRET,user_id:d.user.id,email});}
if(!d.access_token)return Response.json({message:'Conta criada. Confirme seu e-mail e depois entre com sua senha.'});
}else d=await guardedLogin(p.email,p.password,loginControl,()=>auth('token?grant_type=password',{email:p.email,password:p.password}));
if(d.access_token){const opts={httpOnly:true,secure:new URL(req.url).protocol==='https:',sameSite:'lax' as const,path:'/'};c.set('agenda_access',d.access_token,{...opts,maxAge:d.expires_in||3600});c.set('agenda_refresh',d.refresh_token,{...opts,maxAge:60*60*24*30});}return Response.json({ok:true});
}catch(e){if(e instanceof LoginFailure)return Response.json({error:e.message,locked:e.locked,remaining:e.remaining},{status:e.status,headers:{'Cache-Control':'no-store'}});return failure(e);}}
export async function GET(){try{const owner=await getChatGPTUser();const isOwner=!!owner&&owner.email.toLowerCase()===process.env.AGENDA_OWNER_EMAIL?.toLowerCase();const state=isOwner?await rpc('setup_state',{secret:process.env.AGENDA_GATEWAY_SECRET}):null;return Response.json({email:owner?.email||'',isOwner,setupRequired:isOwner&&!state?.configured},{headers:{'Cache-Control':'no-store'}});}catch(e){return failure(e);}}
