import {neonPalettes} from '../../../lib/theme';
import {rpc} from '../../../lib/agenda';
export async function GET(req:Request){
 const slug=new URL(req.url).searchParams.get('tenant');
 let name='Agenda+',icon='/icon-192.png',start='/',palette=neonPalettes.black;
 if(slug){try{const c=await rpc('catalog',{slug});name=c.settings.display_name||c.tenant.name;palette=neonPalettes[c.settings.palette]||neonPalettes.black;start='/'+slug+'/';if(c.settings.logo)icon=c.settings.logo;}catch{}}
 return Response.json({id:start,name,short_name:name.slice(0,20),start_url:start,scope:start,display:'standalone',background_color:palette[3],theme_color:palette[2],lang:'pt-BR',icons:[{src:icon,sizes:icon.startsWith('https:')?'any':'192x192',type:icon.endsWith('.jpg')?'image/jpeg':'image/png'},{src:'/icon-512.png',sizes:'512x512',type:'image/png',purpose:'any maskable'}]},{headers:{'Content-Type':'application/manifest+json','Cache-Control':'no-store'}});
}
