-- Additive update: the existing agenda_api gateway and its permissions are unchanged.
alter table public.plans add column if not exists deleted_at timestamptz;
alter table public.tenants add column if not exists document_type text check(document_type in ('CPF','CNPJ'));
alter table public.tenants add column if not exists document_number text;
alter table public.appointments add column if not exists payment_method text not null default 'A combinar' check(payment_method in ('A combinar','Pix','Dinheiro','Cartão de débito','Cartão de crédito'));
create table public.whatsapp_templates(tenant_id uuid primary key references public.tenants(id),templates jsonb not null);
alter table public.whatsapp_templates enable row level security;
revoke all on public.whatsapp_templates from anon,authenticated;
create policy templates_via_checked_rpc on public.whatsapp_templates to authenticated using(false) with check(false);
create or replace function app_private.valid_document(kind text,input text) returns boolean language plpgsql immutable security invoker set search_path='' as $$
declare s text:=upper(regexp_replace(input,'[^A-Za-z0-9]','','g'));n int;i int;total int;dv int;
begin
if s is null or s ~ '^([A-Z0-9])\1+$' then return false;end if;
if kind='CPF' then
if s !~ '^[0-9]{11}$' then return false;end if;
for n in 9..10 loop total:=0;for i in 1..n loop total:=total+substr(s,i,1)::int*(n+2-i);end loop;dv:=total%11;if dv<2 then dv:=0;else dv:=11-dv;end if;if dv<>substr(s,n+1,1)::int then return false;end if;end loop;
return true;
elsif kind='CNPJ' then
if s !~ '^[A-Z0-9]{12}[0-9]{2}$' then return false;end if;
for n in 12..13 loop total:=0;for i in 1..n loop total:=total+(ascii(substr(s,i,1))-48)*((n-i)%8+2);end loop;dv:=total%11;if dv<2 then dv:=0;else dv:=11-dv;end if;if dv<>substr(s,n+1,1)::int then return false;end if;end loop;
return true;end if;return false;end $$;
create function app_private.delete_plan(p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
update public.plans set deleted_at=now(),active=false where id=(p->>'id')::uuid and deleted_at is null;
if not found then raise exception 'Plano não encontrado ou já excluído.';end if;
insert into public.audit_logs(actor,action) values(auth.uid(),'Exclusão de plano: '||(select name from public.plans where id=(p->>'id')::uuid));
return '{"ok":true}';end $$;
create function app_private.company_save(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;tid uuid;kind text:=coalesce(p->>'document_type','CPF');doc text:=upper(regexp_replace(p->>'document_number','[^A-Za-z0-9]','','g'));
begin
if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
if op not in ('create_tenant','license') then raise exception 'Operação inválida.';end if;
if op='create_tenant' or coalesce(doc,'')<>'' then
if not app_private.valid_document(kind,doc) then raise exception 'Informe um CPF ou CNPJ válido.';end if;
end if;
if op='create_tenant' and not exists(select 1 from public.plans where id=(p->>'plan_id')::uuid and active and deleted_at is null) then raise exception 'Selecione um plano disponível.';end if;
result:=app_private.gateway(op,p);
if op='create_tenant' then select id into tid from public.tenants where slug=p->>'slug';else tid:=(p->>'tenant_id')::uuid;end if;
if coalesce(doc,'')<>'' then update public.tenants set document_type=kind,document_number=doc where id=tid;end if;
return result;
end $$;
create function app_private.appointment_save(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;tid uuid;aid uuid;rol text;method text:=coalesce(nullif(p->>'payment_method',''),'A combinar');
begin
if op not in ('book','appointment','status','payment') then raise exception 'Operação inválida.';end if;
if method not in ('A combinar','Pix','Dinheiro','Cartão de débito','Cartão de crédito') then raise exception 'Forma de pagamento inválida.';end if;
if op='book' then
-- The original booking function validates the server secret, availability and rate limit.
result:=app_private.gateway('book',p);
select id into tid from public.tenants where slug=p->>'slug';
update public.appointments set payment_method=method where tenant_id=tid and protocol=result->>'protocol';
return result||jsonb_build_object('payment_method',method);
end if;
if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
tid:=(p->>'tenant_id')::uuid;rol:=app_private.role(tid);
if rol is null and not app_private.master() then raise exception 'Acesso negado ou licença inativa.';end if;
if op='appointment' then
if rol is distinct from 'admin' and not app_private.master() then raise exception 'Permissão de administrador necessária.';end if;
if p->>'status'='Bloqueado' then return app_private.gateway(op,p);end if;
aid:=coalesce(nullif(p->>'id','')::uuid,gen_random_uuid());p:=p||jsonb_build_object('id',aid);
else
aid:=(p->>'id')::uuid;
if not exists(select 1 from public.appointments where id=aid and tenant_id=tid and (rol='admin' or app_private.master() or professional_id=app_private.own_prof(tid))) then raise exception 'Agendamento não encontrado ou sem permissão.';end if;
end if;
if op<>'payment' then result:=app_private.gateway(op,p);else result:='{"ok":true}';end if;
update public.appointments set payment_method=method where tenant_id=tid and id=aid;
return result;
end $$;
create function app_private.message_templates(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid:=(p->>'tenant_id')::uuid;rol text;key text;
begin
if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
rol:=app_private.role(tid);
if rol is null and not app_private.master() then raise exception 'Acesso negado ou licença inativa.';end if;
if op='get' then return coalesce((select templates from public.whatsapp_templates where tenant_id=tid),'{}');end if;
if op<>'save' or (rol is distinct from 'admin' and not app_private.master()) then raise exception 'Permissão de administrador necessária.';end if;
if jsonb_typeof(p->'templates') is distinct from 'object' then raise exception 'Modelos inválidos.';end if;
foreach key in array array['confirmation','reschedule','cancellation'] loop
if jsonb_typeof(p->'templates'->key) is distinct from 'string' or length(trim(p->'templates'->>key)) not between 1 and 4000 then raise exception 'Preencha os três modelos, com até 4.000 caracteres cada.';end if;
end loop;
insert into public.whatsapp_templates(tenant_id,templates) values(tid,p->'templates') on conflict(tenant_id) do update set templates=excluded.templates;
insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'Modelos de WhatsApp atualizados');
return '{"ok":true}';end $$;
revoke all on function app_private.valid_document(text,text) from public,anon,authenticated;
revoke all on function app_private.delete_plan(jsonb) from public,anon,authenticated;
revoke all on function app_private.company_save(text,jsonb) from public,anon,authenticated;
revoke all on function app_private.appointment_save(text,jsonb) from public,anon,authenticated;
revoke all on function app_private.message_templates(text,jsonb) from public,anon,authenticated;
grant execute on function app_private.delete_plan(jsonb) to authenticated;
grant execute on function app_private.company_save(text,jsonb) to authenticated;
grant execute on function app_private.appointment_save(text,jsonb) to anon,authenticated;
grant execute on function app_private.message_templates(text,jsonb) to authenticated;
create function public.agenda_delete_plan(p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.delete_plan(p)$$;
create function public.agenda_company_save(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.company_save(op,p)$$;
create function public.agenda_appointment_save(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.appointment_save(op,p)$$;
create function public.agenda_message_templates(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.message_templates(op,p)$$;
revoke all on function public.agenda_delete_plan(jsonb) from public,anon,authenticated;
revoke all on function public.agenda_company_save(text,jsonb) from public,anon,authenticated;
revoke all on function public.agenda_appointment_save(text,jsonb) from public,anon,authenticated;
revoke all on function public.agenda_message_templates(text,jsonb) from public,anon,authenticated;
grant execute on function public.agenda_delete_plan(jsonb) to authenticated;
grant execute on function public.agenda_company_save(text,jsonb) to authenticated;
grant execute on function public.agenda_appointment_save(text,jsonb) to anon,authenticated;
grant execute on function public.agenda_message_templates(text,jsonb) to authenticated;
