type Props={scene:'overview'|'resources'|'setup'|'plans'|'access'|'routine';label:string};
export default function SectionBanner({scene}:Props){
 return <div className="sales-section-banner" aria-hidden="true"><img src={`/images/presentation/${scene}.webp`} alt="" loading={scene==='overview'?'eager':'lazy'} decoding="async" width="1536" height="1024"/></div>;
}
