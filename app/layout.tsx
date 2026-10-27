import type {Metadata} from 'next';import './globals.css';import './neon.css';
export const metadata:Metadata={title:'Agenda+ | Seu tempo, bem cuidado.',description:'Agendamento simples e gestão completa para sua barbearia.',icons:{icon:'/favicon.svg',apple:'/icon-192.png'},manifest:'/api/manifest'};
export default function Layout({children}:{children:React.ReactNode}){return <html lang="pt-BR"><body>{children}</body></html>}
