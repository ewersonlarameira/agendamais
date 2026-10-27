import { cookies } from 'next/headers';
export const SB='https://iktpbxfaygcvjkrajycy.supabase.co';
export const KEY='sb_publishable_gaHGqN39-_K7MuRlTV_V1w_6WigfDYM';
export async function rpcNamed(name:string,body:any,token?:string){const c=await cookies();const bearer=token||c.get('agenda_access')?.value;const r=await fetch(SB+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:KEY,...(bearer?{Authorization:'Bearer '+bearer}:{}),'Content-Type':'application/json'},body:JSON.stringify(body),cache:'no-store'});const data:any=await r.json();if(!r.ok)throw new Error(data.message||'Não foi possível concluir.');return data;}
export async function rpc(op:string,p:any={},token?:string){return rpcNamed('agenda_api',{op,p},token)}
export function guard(req:Request){const origin=req.headers.get('origin');if(origin&&origin!==new URL(req.url).origin)throw new Error('Origem inválida.');}
export function failure(e:any){return Response.json({error:e.message||'Falha na solicitação.'},{status:400,headers:{'Cache-Control':'no-store'}});}
