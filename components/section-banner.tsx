type Props={scene:'overview'|'resources'|'setup'|'plans'|'access'|'routine';label:string};
export default function SectionBanner({scene,label}:Props){
 return <div className="sales-section-banner"><img src={`/images/presentation/${scene}.webp`} alt="" aria-hidden="true" loading={scene==='overview'?'eager':'lazy'} decoding="async" width="1536" height="1024"/><div><span>AGENDA+ · DA RESERVA AO ATENDIMENTO</span><p>{label}</p></div></div>;
}
