const CACHE='agenda-static-v3';
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin||!/^\/(icon-192.png|icon-512.png|favicon.svg)$/.test(u.pathname))return;e.respondWith(caches.open(CACHE).then(async c=>{const hit=await c.match(e.request);if(hit)return hit;const r=await fetch(e.request);if(r.ok)c.put(e.request,r.clone());return r;}));});
self.addEventListener('push',event=>{
 let payload={};try{payload=event.data?.json()||{};}catch{}
 event.waitUntil(self.registration.showNotification(payload.title||'🔔 Agenda+',{
  body:payload.body||'Você recebeu uma atualização da sua agenda.',icon:'/icon-192.png',badge:'/icon-192.png',
  tag:payload.tag||'agenda-update',data:payload.data||{url:'/'},renotify:false
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 let target;try{target=new URL(event.notification.data?.url||'/',self.location.origin);}catch{target=new URL('/',self.location.origin);}
 // A push can never redirect the device to an external site.
 if(target.origin!==self.location.origin)target=new URL('/',self.location.origin);
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async windows=>{
  const existing=windows.find(w=>new URL(w.url).origin===target.origin&&new URL(w.url).pathname===target.pathname);
  if(existing){await existing.navigate(target.href);return existing.focus();}
  return self.clients.openWindow(target.href);
 }));
});
