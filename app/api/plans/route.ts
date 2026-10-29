import {SB,KEY} from '../../../lib/agenda';
export async function GET(){
 try{
  // Anonymous credentials on purpose: public plans do not depend on a login cookie.
  const r=await fetch(SB+'/rest/v1/rpc/agenda_public_plans',{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:'{}',cache:'no-store',signal:AbortSignal.timeout(10000)});
  if(!r.ok)throw Error('Plans unavailable: '+r.status);const plans=await r.json();if(!Array.isArray(plans))throw Error('Invalid plans');
  return Response.json({plans},{headers:{'Cache-Control':'no-store, max-age=0','X-Content-Type-Options':'nosniff'}});
 }catch{return Response.json({error:'Não foi possível carregar os planos agora. Tente novamente.'},{status:503,headers:{'Cache-Control':'no-store'}})}
}
