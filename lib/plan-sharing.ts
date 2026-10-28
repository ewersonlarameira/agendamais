type SharePlan={id:string;name:string;amount:number|string;months:number|string;description?:string;active?:boolean;deleted_at?:string|null};
export function availableSharePlans(plans:SharePlan[]){return plans.filter(p=>p.active===true&&!p.deleted_at);}
export function planRenewalLabel(months:number|string){return Number(months)===1?'Mensal':Number(months)===12?'Anual':`A cada ${months} meses`;}
export function plansWhatsAppMessage(plans:SharePlan[],name=''){
 const available=availableSharePlans(plans);if(!available.length)return '';
 const greeting=name.trim()?`Olá, ${name.trim()}! 👋`:'Olá! 👋';
 const options=available.map(p=>{
  const price=Number(p.amount).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
  const period=Number(p.months)===1?'por mês':Number(p.months)===12?'por ano':`a cada ${p.months} meses`;
  return `💳 *${p.name}*\n💰 *${price} ${period}*\n🔄 Renovação: ${planRenewalLabel(p.months).toLowerCase()}\n\n📋 *Descrição e benefícios*\n${p.description?.trim()||'Consulte os detalhes desta assinatura com nossa equipe.'}`;
 });
 return `${greeting}\n\n📅 *Agenda+ — planos de assinatura*\nConheça as opções para organizar e gerenciar seu estabelecimento:\n\n${options.join('\n\n────────────\n\n')}\n\n💬 Qual plano combina melhor com seu negócio? Responda com o nome da opção escolhida ou envie suas dúvidas. Estamos à disposição! 😊\n\nℹ️ Os valores acima correspondem ao período de cada assinatura. A contratação será concluída com nosso atendimento.`;
}

// Desktop bypasses the wa.me → native-app handoff, which may replace astral Unicode.
export function planWhatsAppTarget(userAgent:string,touchPoints=0):'app'|'web'{return /Android|iPhone|iPad|iPod/i.test(userAgent)||(/Macintosh/i.test(userAgent)&&touchPoints>1)?'app':'web';}
