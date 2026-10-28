export function professionalAgendaPath(slug:string){return '/'+encodeURIComponent(slug)+'/agendaprofissional';}
export function professionalPeriod(day:string,view:string){
 if(!/^\d{4}-\d{2}-\d{2}$/.test(day)||!Number.isFinite(Date.parse(day)))throw Error('Data inválida.');
 const start=new Date(day+'T12:00:00Z');let end=new Date(start);
 if(view==='Semana')end.setUTCDate(end.getUTCDate()+6);
 if(view==='Mês'){start.setUTCDate(1);end=new Date(Date.UTC(start.getUTCFullYear(),start.getUTCMonth()+1,0,12));}
 return {from:start.toISOString().slice(0,10),to:end.toISOString().slice(0,10)};
}
export function professionalSaveFields(form:Record<string,any>){
 const {create_access,access_email,initial_password,confirm_password,...professional}=form;
 if(create_access){if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(access_email||'').trim()))throw Error('Informe um e-mail de acesso válido.');if(typeof initial_password!=='string'||initial_password.length<10||new TextEncoder().encode(initial_password).length>72)throw Error('Use uma senha inicial com pelo menos 10 caracteres e até 72 bytes.');if(initial_password!==confirm_password)throw Error('As senhas não coincidem.');if(!professional.active)throw Error('Ative o profissional antes de criar seu acesso.');}
 return {professional,access:create_access?{professional_id:professional.id,email:access_email.trim().toLowerCase(),initial_password,confirm_password}:null};
}
export function newProfessionalId(){
 const bytes=crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
 const hex=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
}
