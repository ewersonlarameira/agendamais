'use client';
import {useEffect,useState} from 'react';
import PlanComparison from './plan-comparison';
import SectionBanner from './section-banner';
import {planRenewalLabel} from '../lib/plan-sharing';
type Plan={id:string;name:string;amount:number|string;months:number;description:string};
export default function PublicPlans(){
 const [plans,P]=useState<Plan[]|null>(null),[error,E]=useState(''),[retry,R]=useState(0);
 useEffect(()=>{
  let cancelled=false;let controller:AbortController|null=null;
  async function refresh(){if(controller)return;controller=new AbortController();try{
   const response=await fetch('/api/plans',{cache:'no-store',signal:controller.signal});const result=await response.json() as {plans?:Plan[];error?:string};
   if(!response.ok||!Array.isArray(result.plans))throw Error(result.error||'Não foi possível carregar os planos.');
   if(!cancelled){P(result.plans);E('')}
  }catch(e){if(!cancelled){P(null);E(e instanceof Error?e.message:'Não foi possível atualizar os planos.')}}finally{controller=null}}
  const visible=()=>{if(document.visibilityState==='visible')void refresh()};
  void refresh();const timer=setInterval(visible,15000);window.addEventListener('focus',visible);document.addEventListener('visibilitychange',visible);
  const channel=typeof BroadcastChannel!=='undefined'?new BroadcastChannel('agenda-public-plans'):null;if(channel)channel.onmessage=()=>void refresh();
  return()=>{cancelled=true;clearInterval(timer);window.removeEventListener('focus',visible);document.removeEventListener('visibilitychange',visible);channel?.close();controller?.abort()};
 },[retry]);
 return <section id="planos" className="sales-plans" aria-labelledby="sales-plans-title"><SectionBanner scene="plans" label="Escolha como organizar o próximo capítulo."/><div className="sales-section-intro"><span className="sales-kicker">PLANOS DE ASSINATURA</span><h2 id="sales-plans-title">Escolha o plano para o seu negócio.</h2><p>Compare os valores, a renovação e o que está incluído em cada assinatura.</p></div>
 {error?<div className="sales-plans-message" role="alert"><p>{error}</p><button className="sales-button sales-button-outline" type="button" onClick={()=>R(r=>r+1)}>Tentar novamente</button></div>:plans===null?<p role="status">Carregando planos…</p>:plans.length?<><PlanComparison plans={plans}/><div className="sales-plan-grid">{plans.map(plan=><article className="sales-plan-card" key={plan.id}><div className="sales-plan-heading"><span className="sales-plan-period">Renovação {planRenewalLabel(plan.months).toLowerCase()}</span><h3>{plan.name}</h3><div className="sales-plan-price"><strong>{Number(plan.amount).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}</strong><span>{plan.months===1?'/ mês':plan.months===12?'/ ano':`a cada ${plan.months} meses`}</span></div></div><div className="sales-plan-description">{plan.description.trim()||'Os detalhes desta assinatura serão disponibilizados em breve.'}</div></article>)}</div></>:<p className="sales-plans-message">Os planos serão disponibilizados em breve.</p>}
 </section>;
}
