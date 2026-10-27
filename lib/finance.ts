export type FinancialEntry={id:string;kind:'income'|'expense';description:string;category:string;amount:number;due_on:string;settled_on:string|null;payment_method:string;notes:string;appointment_id:string|null;voided_at:string|null;version:number};
export type FinancialAppointment={id:string;starts_at:string;status:string;price:number;payment_method:string;customer:string;service:string;professional:string};
export type FinanceData={entries:FinancialEntry[];appointments:FinancialAppointment[]};
export const financeToday=()=>new Date().toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'});
export const financeDate=(s:string)=>s.length===10?s:new Date(s).toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'});
export const financeMoney=(n:number)=>Number(n).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
export const financeDisplayDate=(s:string)=>s?financeDate(s).split('-').reverse().join('/'):'—';
const cents=(n:number)=>Math.round(Number(n)*100);
export function financeTotals(data:FinanceData){
 let income=0,expense=0,pendingIncome=0,pendingExpense=0;
 for(const e of data.entries){if(e.voided_at)continue;const n=cents(e.amount);if(e.settled_on){if(e.kind==='income')income+=n;else expense+=n;}else if(e.kind==='income')pendingIncome+=n;else pendingExpense+=n;}
 const completed=data.appointments.filter(a=>a.status==='Concluído').reduce((s,a)=>s+cents(a.price),0);
 const forecast=data.appointments.filter(a=>a.status!=='Concluído').reduce((s,a)=>s+cents(a.price),0);
 return {income:income/100,expense:expense/100,balance:(income-expense)/100,pendingIncome:(pendingIncome+completed)/100,pendingExpense:pendingExpense/100,forecast:forecast/100};
}
export function financeSlice(entries:FinancialEntry[],appointments:FinancialAppointment[],from:string,to:string):FinanceData{
 return {entries:entries.filter(e=>{const d=e.settled_on||e.due_on;return d>=from&&d<=to}),appointments:appointments.filter(a=>{const d=financeDate(a.starts_at);return d>=from&&d<=to&&!entries.some(e=>!e.voided_at&&e.appointment_id===a.id)})};
}
export function financeCsv(entries:FinancialEntry[]):string{
 // Protect spreadsheet consumers from executable cells, including leading whitespace.
 const cell=(value:unknown)=>'"'+String(value??'').replace(/^(\s*[=+@-])/,'\'$1').replaceAll('"','""')+'"';
 const rows=[['Tipo','Descrição','Categoria','Valor (R$)','Vencimento','Pagamento','Forma de pagamento','Situação','Origem'],...entries.map(e=>[e.kind==='income'?'Receita':'Despesa',e.description,e.category,Number(e.amount).toFixed(2).replace('.',','),financeDisplayDate(e.due_on),e.settled_on?financeDisplayDate(e.settled_on):'',e.payment_method,e.voided_at?'Anulado':e.settled_on?'Pago':'Pendente',e.appointment_id?'Agendamento':'Manual'])];
 return '\uFEFF'+rows.map(row=>row.map(cell).join(';')).join('\r\n');
}
