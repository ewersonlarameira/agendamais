type Guard=(op:string,p:Record<string,unknown>)=>Promise<any>;
export class LoginFailure extends Error{locked:boolean;status:number;remaining?:number;constructor(message:string,status=400,locked=false,remaining?:number){super(message);this.locked=locked;this.status=status;this.remaining=remaining}}
const locked=()=>new LoginFailure('Acesso bloqueado após 5 tentativas incorretas. Entre em contato com o suporte pelo WhatsApp para solicitar o desbloqueio.',423,true,0);
export async function guardedLogin(email:string,password:string,guard:Guard,authenticate:()=>Promise<any>){
 const start=await guard('begin',{email});if(start.locked)throw locked();if(start.busy)throw new LoginFailure('Já existe uma tentativa em andamento para este e-mail. Aguarde e tente novamente.',429);
 let result:any;
 try{result=await authenticate()}catch(e){
  const invalid=(e as any)?.authCode==='invalid_credentials';
  const state=await guard('finish',{email,ticket:start.ticket,outcome:invalid?'invalid':'unavailable'});
  if(state.locked)throw locked();
  if(invalid)throw new LoginFailure(`E-mail ou senha incorretos. Restam ${state.remaining} tentativa(s) antes do bloqueio.`,401,false,state.remaining);
  throw new LoginFailure('Não foi possível validar o acesso agora. Tente novamente. Essa falha não foi contada como senha incorreta.',503);
 }
 const state=await guard('finish',{email,ticket:start.ticket,outcome:'success'});if(state.locked)throw locked();return result;
}
