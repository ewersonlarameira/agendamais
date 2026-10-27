'use client';
import {useCallback,useEffect,useState} from 'react';
import '../app/push.css';
type Props={tenantId:string;demo?:boolean;compact?:boolean;notify:(message:string)=>void};
async function request(op:string,p:Record<string,unknown>){const r=await fetch('/api/push',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({op,p})});const data:any=await r.json();if(!r.ok)throw new Error(data.error||'Não foi possível configurar as notificações.');return data;}
function applicationKey(key:string){const raw=atob(key.replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,c=>c.charCodeAt(0));}
export default function PushControl({tenantId,demo=false,compact=false,notify}:Props){
 const [open,Open]=useState(false);const [supported,Supported]=useState(false);const [ios,IOS]=useState(false);const [installed,Installed]=useState(false);
 const [permission,Permission]=useState<NotificationPermission>('default');const [enabled,Enabled]=useState(false);const [publicKey,PublicKey]=useState('');
 const [loading,Loading]=useState(!demo);const [busy,Busy]=useState(false);const [error,ErrorMessage]=useState('');
 const refresh=useCallback(async()=>{
  const apple=/iPhone|iPad|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
  const standalone=window.matchMedia('(display-mode: standalone)').matches||(navigator as any).standalone===true;
  IOS(apple);Installed(standalone);const ready=window.isSecureContext&&'serviceWorker' in navigator&&'PushManager' in window&&'Notification' in window;Supported(ready);
  if('Notification' in window)Permission(Notification.permission);
  if(demo){Loading(false);return;}
  try{
   const registration=ready?await navigator.serviceWorker.getRegistration('/'):null;const sub=await registration?.pushManager.getSubscription();
   const d=await request('status',{tenant_id:tenantId,endpoint:sub?.endpoint||''});PublicKey(d.publicKey||'');Enabled(!!d.enabled&&!!sub&&Notification.permission==='granted');ErrorMessage('');
  }catch(e:any){ErrorMessage(e.message);Enabled(false);}finally{Loading(false)}
 },[tenantId,demo]);
 useEffect(()=>{void refresh();const listener=()=>{if(document.visibilityState==='visible')void refresh()};document.addEventListener('visibilitychange',listener);window.addEventListener('agenda-push-state',listener);return()=>{document.removeEventListener('visibilitychange',listener);window.removeEventListener('agenda-push-state',listener)}},[refresh]);
 async function enable(){
  if(demo){notify('As notificações ficam disponíveis no ambiente real após entrar na conta.');return;}
  if(!supported||ios&&!installed||!publicKey)return;
  // Permission must be requested directly in this click, before any asynchronous work (iOS).
  Busy(true);ErrorMessage('');
  try{
   const result=await Notification.requestPermission();Permission(result);if(result!=='granted')throw new Error('Permissão não concedida. Você pode permitir notificações nos ajustes do dispositivo.');
   await navigator.serviceWorker.register('/sw.js');const registration=await navigator.serviceWorker.ready;
   let subscription=await registration.pushManager.getSubscription();
   if(subscription){const current=subscription.options.applicationServerKey;const expected=applicationKey(publicKey);const actual=current?new Uint8Array(current):null;if(!actual||actual.length!==expected.length||actual.some((n,i)=>n!==expected[i])){await subscription.unsubscribe();subscription=null;}}
   if(!subscription)subscription=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:applicationKey(publicKey)});
   await request('register',{tenant_id:tenantId,subscription:subscription.toJSON()});Enabled(true);window.dispatchEvent(new Event('agenda-push-state'));notify('🔔 Notificações ativadas neste dispositivo para esta empresa.');
  }catch(e:any){ErrorMessage(e.message||'Não foi possível ativar.');}finally{Busy(false)}
 }
 async function disable(){Busy(true);try{const reg=await navigator.serviceWorker.getRegistration('/');const sub=await reg?.pushManager.getSubscription();if(sub)await request('unregister',{tenant_id:tenantId,endpoint:sub.endpoint});Enabled(false);window.dispatchEvent(new Event('agenda-push-state'));notify('Notificações desta empresa desativadas neste dispositivo.');}catch(e:any){ErrorMessage(e.message)}finally{Busy(false)}}
 async function test(){Busy(true);try{const reg=await navigator.serviceWorker.getRegistration('/');const sub=await reg?.pushManager.getSubscription();if(!sub)throw new Error('Ative as notificações novamente.');await request('test',{tenant_id:tenantId,endpoint:sub.endpoint});notify('Teste solicitado. Aguarde a notificação do sistema.');}catch(e:any){ErrorMessage(e.message)}finally{Busy(false)}}
 const content=<div className="push-content"><div className="push-status"><span>{enabled?'🔔':'🔕'}</span><div><strong>{demo?'Prévia das notificações':enabled?'Ativadas neste dispositivo':'Receba novos agendamentos'}</strong><p>{enabled?'Os próximos agendamentos serão enviados para este aparelho.':'Ative os avisos para acompanhar sua agenda mesmo com o app fechado.'}</p></div></div>
  <div className="push-example"><span className="eyebrow">EXEMPLO DEMONSTRATIVO</span><strong>💈 Novo agendamento · Sua barbearia</strong><p>👤 Cliente de exemplo<br/>✂️ Corte masculino<br/>📅 terça-feira, 27/10/2026<br/>🕒 14:00</p></div>
  <p>O aviso contém nome do cliente, procedimento, data, dia da semana e horário de Brasília. Esses dados podem aparecer na tela bloqueada do aparelho.</p>
  <p className="tiny">Administradores recebem os novos agendamentos da empresa. Profissionais recebem somente os próprios. Ao tocar no aviso, a agenda abre na data do atendimento.</p>
  {ios&&!installed&&<p className="notice">📱 No iPhone ou iPad, use o Safari → Compartilhar → Adicionar à Tela de Início. Abra o Agenda+ pelo ícone instalado e ative os avisos aqui (iOS/iPadOS 16.4 ou posterior).</p>}
  {!demo&&!supported&&!(ios&&!installed)&&<p className="notice">Este navegador não oferece notificações Push neste contexto. Abra o aplicativo instalado em um navegador compatível e com HTTPS.</p>}
  {!demo&&permission==='denied'&&<p className="notice">As notificações estão bloqueadas. Permita os avisos nas configurações do navegador ou do aplicativo no dispositivo e volte aqui.</p>}
  {error&&<p className="notice" role="alert">{error}</p>}
  {!demo&&!loading&&!publicKey&&!error&&<p className="notice">O serviço de notificações está sendo configurado. Tente novamente em instantes.</p>}
  <div className="push-actions">{enabled?<><button type="button" className="primary" disabled={busy} onClick={()=>void test()}>🔔 Enviar notificação de teste</button><button type="button" className="secondary" disabled={busy} onClick={()=>void disable()}>Desativar neste dispositivo</button></>:<button type="button" className="primary" disabled={busy||loading||(!demo&&(!supported||ios&&!installed||permission==='denied'||!publicKey))} onClick={()=>void enable()}>{busy?'Ativando…':loading?'Verificando…':'🔔 Ativar notificações neste dispositivo'}</button>}<button type="button" className="textbutton" disabled={busy||loading} onClick={()=>void refresh()}>Atualizar estado</button></div>
  <p className="tiny">Ative em cada aparelho desejado. Não há envio retroativo dos agendamentos anteriores à ativação. A exibição depende da conexão e das permissões do sistema, incluindo o modo Foco/Não Perturbe.</p>
 </div>;
 if(!compact)return content;
 return <><button type="button" className={'iconbtn push-bell '+(enabled?'push-on':'')} aria-label="Notificações do dispositivo" title="Notificações do dispositivo" onClick={()=>Open(true)}>{enabled?'🔔':'🔕'}</button>{open&&<div className="overlay" onMouseDown={e=>e.target===e.currentTarget&&!busy&&Open(false)}><section className="modal" role="dialog" aria-modal="true" aria-label="Notificações do dispositivo"><header><div><span className="eyebrow">AGENDA+</span><h2>🔔 Notificações</h2></div><button type="button" className="iconbtn" aria-label="Fechar notificações" disabled={busy} onClick={()=>Open(false)}>✕</button></header>{content}</section></div>}</>;
}
