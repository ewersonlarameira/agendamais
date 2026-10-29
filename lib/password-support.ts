import {whatsappUrl} from './whatsapp';
// 0 is the domestic dialing prefix; WhatsApp uses country code + DDD + subscriber.
export const passwordSupportPhone='5524999074698';
export function passwordSupportMessage(email='',pathname='/',origin=''){
 const parts=pathname.split('/').filter(Boolean);const slug=parts[0]||'';
 const context=slug==='master'?'👑 Painel: Administrador Master':/^[a-z][a-z0-9-]{2,49}$/.test(slug)?'🏪 Estabelecimento: /'+slug:'';
 const account=/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())?'📧 E-mail de acesso: '+email.trim().slice(0,254):'📧 Informarei meu e-mail de acesso no atendimento.';
 let link='';try{const url=new URL(pathname,origin);if(['http:','https:'].includes(url.protocol)){url.search='';url.hash='';link='🔗 Painel: '+url.href;}}catch{}
 return ['Olá! 👋 Preciso de ajuda para redefinir minha senha de acesso ao Agenda+.','',[context,account,link].filter(Boolean).join('\n'),'','Podem me orientar na recuperação do acesso?'].join('\n');
}
export function passwordSupportUrl(email='',pathname='/',origin=''){return whatsappUrl(passwordSupportPhone,passwordSupportMessage(email,pathname,origin));}

export function unlockSupportMessage(email='',pathname='/',origin=''){return passwordSupportMessage(email,pathname,origin).replace('Preciso de ajuda para redefinir minha senha de acesso ao Agenda+.','Meu acesso ao Agenda+ foi bloqueado após 5 tentativas incorretas de login ou senha.').replace('Podem me orientar na recuperação do acesso?','Solicito a verificação da minha identidade e o desbloqueio do acesso. Podem me ajudar?');}
export function unlockSupportUrl(email='',pathname='/',origin=''){return whatsappUrl(passwordSupportPhone,unlockSupportMessage(email,pathname,origin));}
