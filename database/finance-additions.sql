-- Additive Finance module. Existing booking/auth gateways remain unchanged.
create table public.financial_entries (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id),
 kind text not null check(kind in ('income','expense')),
 description text not null check(length(trim(description)) between 3 and 180),
 category text not null check(length(trim(category)) between 1 and 60),
 amount numeric(10,2) not null check(amount>0 and amount<100000000),
 due_on date not null,
 settled_on date,
 payment_method text not null default 'A combinar' check(payment_method in ('A combinar','Pix','Dinheiro','Cartão de débito','Cartão de crédito')),
 notes text not null default '' check(length(notes)<=2000),
 appointment_id uuid references public.appointments(id),
 voided_at timestamptz,
 version int not null default 1,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(appointment_id is null or kind='income'),
 check(settled_on is null or payment_method<>'A combinar')
);
create index financial_due on public.financial_entries(tenant_id,due_on);
create index financial_settled on public.financial_entries(tenant_id,settled_on) where settled_on is not null;
create unique index financial_appointment_once on public.financial_entries(appointment_id) where appointment_id is not null and voided_at is null;
alter table public.financial_entries enable row level security;
revoke all on public.financial_entries from public,anon,authenticated;
create policy finance_checked_rpc_only on public.financial_entries to authenticated using(false) with check(false);

create function app_private.finance(op text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 tid uuid:=(p->>'tenant_id')::uuid; eid uuid; aid uuid; current_entry public.financial_entries;
 a public.appointments; first_day date; last_day date; paid date; due date; total numeric;
 method text; title text; cat text; typ text; result jsonb; expected int;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
 if tid is null or (app_private.role(tid) is distinct from 'admin' and not app_private.master()) then raise exception 'Acesso financeiro restrito ao administrador da empresa.';end if;
 if not exists(select 1 from public.tenants t join public.licenses l on l.tenant_id=t.id where t.id=tid and t.status='active' and (now() at time zone 'America/Sao_Paulo')::date between l.starts_on and l.expires_on) then raise exception 'Empresa suspensa ou licença inativa.';end if;
 if op='get' then
  first_day:=(p->>'from')::date;last_day:=(p->>'to')::date;
  if first_day is null or last_day is null or last_day<first_day or last_day-first_day>365 then raise exception 'Selecione um período de até 366 dias.';end if;
  -- Cash accounting: settled entries use actual payment date; pending use due date.
  -- Never return unrelated tenant data or load the full historical ledger.
  select jsonb_build_object('entries',coalesce((select jsonb_agg(to_jsonb(e) order by coalesce(e.settled_on,e.due_on) desc,e.created_at desc) from public.financial_entries e where e.tenant_id=tid and coalesce(e.settled_on,e.due_on) between first_day and last_day),'[]'),
   'appointments',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'starts_at',ap.starts_at,'status',ap.status,'price',ap.price,'payment_method',ap.payment_method,'customer',c.name,'service',s.name,'professional',pr.name) order by ap.starts_at) from public.appointments ap join public.customers c on c.id=ap.customer_id and c.tenant_id=tid join public.services s on s.id=ap.service_id and s.tenant_id=tid join public.professionals pr on pr.id=ap.professional_id and pr.tenant_id=tid where ap.tenant_id=tid and ap.starts_at>=first_day::timestamp at time zone 'America/Sao_Paulo' and ap.starts_at<(last_day+1)::timestamp at time zone 'America/Sao_Paulo' and ap.status in ('Agendado','Confirmado','Concluído') and ap.price>0 and not exists(select 1 from public.financial_entries f where f.tenant_id=tid and f.appointment_id=ap.id and f.voided_at is null)),'[]')) into result;
  return result;
 end if;
 if op not in ('save','settle','void') then raise exception 'Operação financeira inválida.';end if;
 eid:=nullif(p->>'id','')::uuid;
 if eid is not null then
  select * into current_entry from public.financial_entries where id=eid and tenant_id=tid for update;
  if not found then raise exception 'Lançamento não encontrado nesta empresa.';end if;
  expected:=(p->>'version')::int;
  if expected is null or expected<>current_entry.version or current_entry.voided_at is not null then raise exception 'Este lançamento foi alterado. Atualize o financeiro e tente novamente.';end if;
 elsif op<>'save' then raise exception 'Selecione o lançamento.';end if;
 if op='void' then
  update public.financial_entries set voided_at=now(),version=version+1,updated_at=now() where id=eid and tenant_id=tid;
 else
  paid:=nullif(p->>'settled_on','')::date;method:=coalesce(p->>'payment_method','A combinar');
  if paid>(now() at time zone 'America/Sao_Paulo')::date then raise exception 'A data de pagamento não pode estar no futuro.';end if;
  if method not in ('A combinar','Pix','Dinheiro','Cartão de débito','Cartão de crédito') or (paid is not null and method='A combinar') then raise exception 'Informe a forma de pagamento realizada.';end if;
  if op='settle' then
   if current_entry.settled_on is not null then raise exception 'Pagamento já registrado.';end if;
   if paid is null then raise exception 'Informe a data de pagamento.';end if;
   update public.financial_entries set settled_on=paid,payment_method=method,version=version+1,updated_at=now() where id=eid and tenant_id=tid;
  else
   aid:=nullif(p->>'appointment_id','')::uuid;
   if eid is not null and (aid is distinct from current_entry.appointment_id or p->>'kind' is distinct from current_entry.kind) then raise exception 'Não é permitido trocar a origem ou o tipo do lançamento.';end if;
   typ:=p->>'kind';due:=(p->>'due_on')::date;cat:=trim(p->>'category');title:=trim(p->>'description');
   if aid is not null then
    select * into a from public.appointments where id=aid and tenant_id=tid for update;
    if not found then raise exception 'Agendamento não pertence a esta empresa.';end if;
    if eid is null and a.status not in ('Agendado','Confirmado','Concluído') then raise exception 'O agendamento está cancelado ou indisponível.';end if;
    total:=case when eid is null then a.price else current_entry.amount end;typ:='income';cat:='Atendimentos';
    title:='Atendimento · '||(select name from public.services where id=a.service_id and tenant_id=tid);
   else
    if coalesce(p->>'amount','') !~ '^[0-9]+(\.[0-9]{1,2})?$' then raise exception 'Informe um valor com até duas casas decimais.';end if;
    total:=(p->>'amount')::numeric;
   end if;
   if typ is null or typ not in ('income','expense') or due is null or title is null or length(title) not between 3 and 180 or cat is null or length(cat) not between 1 and 60 or total is null or total<=0 or total>=100000000 or length(coalesce(p->>'notes',''))>2000 then raise exception 'Revise descrição, categoria, data e valor do lançamento.';end if;
   if eid is null then
    insert into public.financial_entries(tenant_id,kind,description,category,amount,due_on,settled_on,payment_method,notes,appointment_id) values(tid,typ,title,cat,total,due,paid,method,coalesce(p->>'notes',''),aid) returning id into eid;
   else
    update public.financial_entries set description=title,category=cat,amount=total,due_on=due,settled_on=paid,payment_method=method,notes=coalesce(p->>'notes',''),version=version+1,updated_at=now() where id=eid and tenant_id=tid;
   end if;
  end if;
 end if;
 insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'finance:'||op||' · '||eid::text||' · anterior='||coalesce(to_jsonb(current_entry)::text,'null')||' · atual='||(select to_jsonb(e)::text from public.financial_entries e where e.id=eid and e.tenant_id=tid));
 return jsonb_build_object('ok',true,'id',eid);
exception when unique_violation then raise exception 'Este agendamento já possui um lançamento financeiro. Atualize a lista.';
end $$;
revoke all on function app_private.finance(text,jsonb) from public,anon,authenticated;
grant execute on function app_private.finance(text,jsonb) to authenticated;
create function public.agenda_finance(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.finance(op,p)$$;
revoke all on function public.agenda_finance(text,jsonb) from public,anon,authenticated;
grant execute on function public.agenda_finance(text,jsonb) to authenticated;
