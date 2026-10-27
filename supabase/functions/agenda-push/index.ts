// @deno-types="npm:@types/web-push@3.6.4"
import webpush from 'npm:web-push@3.6.7';
import {timingSafeEqual,createECDH,randomBytes} from 'node:crypto';
import {allowedPushEndpoint,pushPayload} from './payload.ts';

// Only the database dispatcher knows this endpoint's private authentication key.
// Supabase's built-in service role stays inside the Edge runtime, never in Sites/browser/source.
async function rpc(op:string,p:Record<string,unknown>={}){
 const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const url=Deno.env.get('SUPABASE_URL');
 if(!key||!url)throw new Error('Push service is not configured');
 const r=await fetch(url+'/rest/v1/rpc/agenda_push_worker',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({op,p}),signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw new Error('Push queue RPC failed: '+r.status);
 return await r.json();
}
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 const supplied=req.headers.get('x-agenda-push')||'';
 if(!/^[a-f0-9]{64}$/.test(supplied))return new Response('Unauthorized',{status:401});
 try{
  const config=await rpc('config');const expected=config?.push_dispatch||'';
  if(expected.length!==supplied.length||!timingSafeEqual(new TextEncoder().encode(expected),new TextEncoder().encode(supplied)))return new Response('Unauthorized',{status:401});
  if(!config.push_vapid_public||!config.push_vapid_private||!config.push_origin)return new Response('Service unavailable',{status:503});
  if(req.headers.get('x-agenda-check')==='crypto'){
   const receiver=createECDH('prime256v1');receiver.generateKeys();
   const details=webpush.generateRequestDetails({endpoint:'https://fcm.googleapis.com/fcm/send/agenda-self-test',keys:{p256dh:receiver.getPublicKey().toString('base64url'),auth:randomBytes(16).toString('base64url')}},JSON.stringify({title:'Agenda+ encryption self-test'}),{TTL:60,contentEncoding:'aes128gcm',vapidDetails:{subject:config.push_origin,publicKey:config.push_vapid_public,privateKey:config.push_vapid_private}});
   return Response.json({ok:!!details.body?.length,encryption:new Headers(details.headers).get('content-encoding')},{headers:{'Cache-Control':'no-store'}});
  }
  const jobs=await rpc('claim');let sent=0;let failed=0;
  // Small parallel groups stay within Edge wall-clock and provider limits.
  for(let offset=0;offset<jobs.length;offset+=5){await Promise.all(jobs.slice(offset,offset+5).map(async(job:any)=>{
   let status=0;let state='retry';
   try{
    if(!allowedPushEndpoint(job.subscription.endpoint))throw new Error('Invalid push destination');
    const details=webpush.generateRequestDetails(job.subscription,JSON.stringify(pushPayload(job)),{TTL:3600,urgency:'high',contentEncoding:'aes128gcm',vapidDetails:{subject:config.push_origin,publicKey:config.push_vapid_public,privateKey:config.push_vapid_private}});
    const response=await fetch(details.endpoint,{method:details.method,headers:details.headers,body:details.body,redirect:'error',signal:AbortSignal.timeout(10000)});
    status=response.status;await response.body?.cancel();
    state=response.ok?'sent':[404,410].includes(status)?'gone':status===429||status>=500?'retry':'failed';
   }catch{state=allowedPushEndpoint(job.subscription.endpoint)?'retry':'failed';}
   if(state==='sent')sent++;else failed++;
   await rpc('finish',{id:job.id,lease:job.lease,state,status});
  }));}
  return Response.json({processed:jobs.length,sent,failed},{headers:{'Cache-Control':'no-store'}});
 }catch{return new Response('Push dispatch unavailable',{status:503});}
});
