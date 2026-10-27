export function allowedPushEndpoint(endpoint:string):boolean{
 try{const u=new URL(endpoint);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&(u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||u.hostname==='web.push.apple.com'||/^[a-z0-9-]+\.notify\.windows\.com$/.test(u.hostname))&&u.pathname.length>1;}catch{return false;}
}
export function pushPayload(job:any){
 const slug=job.tenant.slug;
 if(!/^[a-z][a-z0-9-]{2,49}$/.test(slug))throw new Error('Invalid tenant slug');
 if(job.event==='test')return {title:'🔔 Agenda+ · Notificações ativadas',body:'Este dispositivo está pronto para receber novos agendamentos de '+job.tenant.name+'.',tag:'agenda-push-test',data:{url:'/'+slug+'/admin'}};
 const a=job.appointment;if(!a?.customer||!a?.service||!a?.starts_at)throw new Error('Missing appointment details');
 const dt=new Date(a.starts_at);if(!Number.isFinite(dt.getTime()))throw new Error('Invalid booking time');
 const opts={timeZone:'America/Sao_Paulo'};
 const day=dt.toLocaleDateString('pt-BR',{...opts,weekday:'long'});
 const date=dt.toLocaleDateString('pt-BR',opts);
 const time=dt.toLocaleTimeString('pt-BR',{...opts,hour:'2-digit',minute:'2-digit',hour12:false});
 const iso=dt.toLocaleDateString('en-CA',opts);
 return {title:'💈 Novo agendamento · '+job.tenant.name,body:'👤 '+a.customer+'\n✂️ '+a.service+'\n📅 '+day+', '+date+'\n🕒 '+time,
  tag:'agenda-booking-'+a.id,data:{url:'/'+slug+'/admin?date='+iso+'&appointment='+encodeURIComponent(a.id)}};
}
