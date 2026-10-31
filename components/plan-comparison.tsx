type Plan={id:string;name:string;amount:number|string;months:number;description:string};
const normalize=(value:string)=>value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
const clean=(value:string)=>value.replace(/^[^\p{L}\p{N}]+/u,'').replace(/[;.]$/,'').trim();
function benefits(plan:Plan){return plan.description.replace(/\\n/g,'\n').split('\n').map(clean).filter(line=>line&&!/^(para |recursos apresentados|notificacoes dependem|o envio das mensagens)/.test(normalize(line)));}
const groups:[string,RegExp][]=[['Aplicativo instalável',/pwa|aplicativo/],['Notificações',/notifica/],['Acessos da equipe',/acessos individuais|acessos?\)/],['Agenda do funcionário',/propria agenda/],['Expediente e bloqueios',/jornadas|intervalos e bloqueios/],['Identidade visual',/paletas|personaliza.*logo/],['Exportação financeira',/csv|exporta/],['Mensagens de WhatsApp',/whatsapp/],['Página pública',/pagina publica/],['Regras de reserva',/antecedencia|prazo de reserva/],['Suporte',/suporte/]];
const group=(line:string)=>groups.find(([,pattern])=>pattern.test(normalize(line)));
const money=(amount:number|string)=>Number(amount).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
export default function PlanComparison({plans}:{plans:Plan[]}){
 const professional=plans.find(p=>/^plano\s+profissional$/i.test(p.name.trim()));
 const premium=plans.find(p=>/^plano\s+premium$/i.test(p.name.trim()));
 if(!professional||!premium)return null;
 const base=benefits(professional),extras=benefits(premium);
 const inherits=/recursos apresentados no plano profissional/i.test(premium.description);
 const difference=Number(premium.amount)-Number(professional.amount);
 return <div className="sales-comparison" aria-labelledby="sales-comparison-title">
  <div className="sales-comparison-intro"><span className="sales-kicker">PROFISSIONAL OU PREMIUM?</span><h3 id="sales-comparison-title">Veja o que muda em cada plano.</h3><p>{inherits?'O Premium reúne os recursos do Profissional e os benefícios destacados abaixo.':'Compare os benefícios descritos em cada assinatura.'}</p>{professional.months===premium.months&&difference>0&&<span className="sales-comparison-upgrade">Premium por mais {money(difference)} {premium.months===1?'por mês':premium.months===12?'por ano':`a cada ${premium.months} meses`}</span>}</div>
  <div className="sales-comparison-scroll" tabIndex={0} role="region" aria-label="Tabela comparativa dos planos"><table><caption>Comparação das condições publicadas pelo Agenda+</caption><thead><tr><th scope="col">Recurso</th>{[professional,premium].map(p=><th scope="col" key={p.id}><span>{p.name}</span><strong>{money(p.amount)}</strong><small>{p.months===1?'por mês':p.months===12?'por ano':`a cada ${p.months} meses`}</small></th>)}</tr></thead><tbody>
  {inherits&&<tr><th scope="row">Recursos do Profissional</th><td><span className="sales-comparison-check">✓</span> Incluídos</td><td><span className="sales-comparison-check">✓</span> Todos incluídos</td></tr>}
  {extras.map(line=>{const feature=group(line);const match=feature?base.find(b=>group(b)?.[0]===feature[0]):base.find(b=>normalize(b)===normalize(line));return <tr key={line}><th scope="row">{feature?.[0]||line}</th><td>{match||<span className="sales-comparison-unspecified">Não destacado</span>}</td><td><span className="sales-comparison-check" aria-hidden="true">✓ </span>{line}</td></tr>})}
  </tbody></table></div>
  <p className="sales-comparison-note">“Não destacado” significa que o benefício não está especificado na descrição do Profissional. Confira os detalhes completos dos planos abaixo.</p>
 </div>;
}
