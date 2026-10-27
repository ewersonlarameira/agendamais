create extension if not exists btree_gist;
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
create table app_private.secrets(key text primary key,value text not null);
create table public.platform_admins(user_id uuid primary key references auth.users(id));
create table public.plans(id uuid primary key default gen_random_uuid(),name text not null,amount numeric(10,2) not null check(amount>=0),months int not null check(months>0),active boolean not null default true);
insert into public.plans(name,amount,months) values ('Mensal',0,1),('Trimestral',0,3),('Anual',0,12);
create table public.tenants(id uuid primary key default gen_random_uuid(),name text not null,slug text not null unique check(slug ~ '^[a-z][a-z0-9-]{2,49}$' and slug not in ('master','admin','api','signin-with-chatgpt','signout-with-chatgpt','callback','privacidade','termos','manifest','demo','favicon','assets','_next')),responsible text not null,email text not null,phone text not null default '',status text not null default 'active' check(status in ('active','suspended')),created_at timestamptz not null default now());
create table public.licenses(id uuid primary key default gen_random_uuid(),tenant_id uuid not null unique references public.tenants(id),plan_id uuid references public.plans(id),starts_on date not null,expires_on date not null,amount numeric(10,2) not null default 0 check(amount>=0),paid boolean not null default false,check(expires_on>=starts_on));
create table public.memberships(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),email text not null,user_id uuid references auth.users(id),role text not null check(role in ('admin','professional')),professional_id uuid,active boolean not null default true,unique(tenant_id,email));
create table public.settings(tenant_id uuid primary key references public.tenants(id),data jsonb not null default '{"palette":"black","welcome":"Seu próximo cuidado começa aqui.","opening":"09:00","closing":"18:00","days":[1,2,3,4,5,6],"min_notice":60,"max_days":30,"interval":15,"timezone":"America/Sao_Paulo"}');
create table public.services(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),name text not null,duration int not null check(duration between 5 and 600),price numeric(10,2) not null check(price>=0),emoji text not null default '✂️',active boolean not null default true,unique(tenant_id,id));
create table public.professionals(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),name text not null,phone text not null default '',photo text not null default '',active boolean not null default true,schedule jsonb not null default '{}',service_ids uuid[] not null default '{}',unique(tenant_id,id));
create table public.customers(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),name text not null,phone text not null,birthday date,notes text not null default '',created_at timestamptz not null default now(),unique(tenant_id,phone),unique(tenant_id,id));
create table public.appointments(id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),professional_id uuid not null,service_id uuid,customer_id uuid,starts_at timestamptz not null,ends_at timestamptz not null,price numeric(10,2) not null default 0,status text not null default 'Agendado' check(status in ('Agendado','Confirmado','Concluído','Cancelado','Não compareceu','Bloqueado')),protocol text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),notes text not null default '',created_at timestamptz not null default now(),foreign key(tenant_id,professional_id) references public.professionals(tenant_id,id),foreign key(tenant_id,service_id) references public.services(tenant_id,id),foreign key(tenant_id,customer_id) references public.customers(tenant_id,id),check(ends_at>starts_at),exclude using gist(tenant_id with =, professional_id with =,tstzrange(starts_at,ends_at,'[)') with &&) where(status not in ('Cancelado','Não compareceu')));
create table public.audit_logs(id bigint generated always as identity primary key,tenant_id uuid references public.tenants(id),actor uuid,action text not null,created_at timestamptz not null default now());
create table app_private.rate_limits(key text primary key,window_start timestamptz not null default now(),count int not null default 1);
create index on public.memberships(user_id,tenant_id);
create index on public.memberships(lower(email));
create index on public.services(tenant_id);
create index on public.professionals(tenant_id);
create index on public.customers(tenant_id);
create index on public.appointments(tenant_id,starts_at);
create index on public.audit_logs(tenant_id,created_at);
create index on public.licenses(plan_id);
create index on public.appointments(customer_id);
create index on public.appointments(service_id);
create or replace function app_private.master() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.platform_admins where user_id=auth.uid())$$;
create or replace function app_private.role(t uuid) returns text language sql stable security definer set search_path='' as $$select m.role from public.memberships m join public.tenants e on e.id=m.tenant_id join public.licenses l on l.tenant_id=e.id join auth.users u on u.id=auth.uid() where m.tenant_id=t and m.active and e.status='active' and l.starts_on<=(now() at time zone 'America/Sao_Paulo')::date and l.expires_on>=(now() at time zone 'America/Sao_Paulo')::date and u.email_confirmed_at is not null and (m.user_id=u.id or lower(m.email)=lower(u.email)) limit 1$$;
create or replace function app_private.own_prof(t uuid) returns uuid language sql stable security definer set search_path='' as $$select m.professional_id from public.memberships m join auth.users u on u.id=auth.uid() where m.tenant_id=t and m.active and (m.user_id=u.id or lower(m.email)=lower(u.email)) limit 1$$;
-- All business data goes through the checked RPC gateway. No direct Data API grants.
do $$ declare x text; begin foreach x in array array['platform_admins','plans','tenants','licenses','memberships','settings','services','professionals','customers','appointments','audit_logs'] loop execute format('alter table public.%I enable row level security',x);execute format('revoke all on public.%I from anon,authenticated',x);execute format('create policy gateway_only on public.%I to authenticated using(false) with check(false)',x);end loop;end $$;
create or replace function app_private.slots(t uuid,s uuid,p uuid,d date) returns table(professional_id uuid,starts_at timestamptz) language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb; pro record; sv public.services; z text; op time; cl time; v timestamptz; finish timestamptz; dow int;
begin
select data into cfg from public.settings where tenant_id=t; z:=coalesce(cfg->>'timezone','America/Sao_Paulo');
if not exists(select 1 from public.tenants e join public.licenses l on l.tenant_id=e.id where e.id=t and e.status='active' and (now() at time zone 'America/Sao_Paulo')::date between l.starts_on and l.expires_on) then return;end if;
select * into sv from public.services where id=s and tenant_id=t and active;if not found then return;end if;
if d<(now() at time zone z)::date or d>(now() at time zone z)::date+coalesce((cfg->>'max_days')::int,30) then return;end if;
dow:=extract(dow from d); if not coalesce(cfg->'days','[1,2,3,4,5,6]') @> to_jsonb(dow) then return;end if;
if coalesce(cfg->'holidays','[]') @> to_jsonb(d::text) then return;end if;
for pro in select * from public.professionals pr where pr.tenant_id=t and pr.active and (p is null or pr.id=p) and s=any(pr.service_ids) loop
if pro.schedule ? 'days' and not (pro.schedule->'days' @> to_jsonb(dow)) then continue;end if;
op:=greatest(coalesce(nullif(cfg->>'opening','')::time,'09:00'),coalesce(nullif(pro.schedule->>'opening','')::time,'00:00'));
cl:=least(coalesce(nullif(cfg->>'closing','')::time,'18:00'),coalesce(nullif(pro.schedule->>'closing','')::time,'23:59'));
v:=(d+op) at time zone z; finish:=(d+cl) at time zone z;
while v+make_interval(mins=>sv.duration)<=finish loop
if v>=now()+make_interval(mins=>coalesce((cfg->>'min_notice')::int,60)) and not exists(select 1 from public.appointments a where a.tenant_id=t and a.professional_id=pro.id and a.status not in ('Cancelado','Não compareceu') and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(v,v+make_interval(mins=>sv.duration),'[)')) and not (coalesce(cfg->>'break_start','')<>'' and coalesce(cfg->>'break_end','')<>'' and tstzrange(v,v+make_interval(mins=>sv.duration),'[)') && tstzrange((d+(cfg->>'break_start')::time) at time zone z,(d+(cfg->>'break_end')::time) at time zone z,'[)')) and not (coalesce(pro.schedule->>'break_start','')<>'' and coalesce(pro.schedule->>'break_end','')<>'' and tstzrange(v,v+make_interval(mins=>sv.duration),'[)') && tstzrange((d+(pro.schedule->>'break_start')::time) at time zone z,(d+(pro.schedule->>'break_end')::time) at time zone z,'[)')) then professional_id:=pro.id;starts_at:=v;return next;end if;
v:=v+make_interval(mins=>greatest(5,coalesce((cfg->>'interval')::int,15)));end loop;end loop;end $$;
create or replace function app_private.gateway(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid; rid uuid; role_name text; x jsonb; v jsonb; obj text; tab text; sv public.services; pro uuid; ts timestamptz; cid uuid; aid uuid; secret text; cnt int; cfg jsonb;
begin
if op='catalog' then
select e.id into t from public.tenants e join public.licenses l on l.tenant_id=e.id where e.slug=p->>'slug' and e.status='active' and (now() at time zone 'America/Sao_Paulo')::date between l.starts_on and l.expires_on;
if t is null then raise exception 'Estabelecimento indisponível ou licença inativa.';end if;
return jsonb_build_object('tenant',(select jsonb_build_object('id',id,'name',name,'slug',slug) from public.tenants where id=t),'settings',(select data from public.settings where tenant_id=t),'services',coalesce((select jsonb_agg(to_jsonb(s)-'tenant_id') from public.services s where tenant_id=t and active),'[]'),'professionals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'photo',photo,'service_ids',service_ids)) from public.professionals where tenant_id=t and active),'[]'));
end if;
if op='slots' then select id into t from public.tenants where slug=p->>'slug';return coalesce((select jsonb_agg(to_jsonb(s)) from app_private.slots(t,(p->>'service_id')::uuid,nullif(p->>'professional_id','')::uuid,(p->>'date')::date) s),'[]');end if;
if op='setup_state' then
select value into secret from app_private.secrets where key='gateway';
if secret is null or p->>'secret' is distinct from secret then raise exception 'Acesso negado.';end if;
return jsonb_build_object('configured',exists(select 1 from public.platform_admins));
end if;
if op='bootstrap' then
select value into secret from app_private.secrets where key='gateway';if secret is null or p->>'secret' is distinct from secret then raise exception 'Acesso negado.';end if;
perform pg_advisory_xact_lock(887711);
if exists(select 1 from public.platform_admins) then raise exception 'Master já configurado.';end if;
if not exists(select 1 from auth.users where id=(p->>'user_id')::uuid and lower(email)=lower(p->>'email')) then raise exception 'Conta inválida.';end if;
insert into public.platform_admins values((p->>'user_id')::uuid);return '{"ok":true}';end if;
if op='book' then
select value into secret from app_private.secrets where key='gateway';if secret is null or p->>'secret' is distinct from secret then raise exception 'Acesso negado.';end if;
insert into app_private.rate_limits(key) values(p->>'ip') on conflict(key) do update set count=case when app_private.rate_limits.window_start<now()-interval '1 hour' then 1 else app_private.rate_limits.count+1 end,window_start=case when app_private.rate_limits.window_start<now()-interval '1 hour' then now() else app_private.rate_limits.window_start end returning count into cnt;
if cnt>20 then raise exception 'Limite de solicitações. Tente mais tarde.';end if;
select id into t from public.tenants where slug=p->>'slug';
if length(trim(p->>'name'))<3 or length(p->>'name')>120 or (p->>'phone') !~ '^[0-9]{10,13}$' then raise exception 'Informe nome completo e WhatsApp válido.';end if;
select * into sv from public.services where tenant_id=t and id=(p->>'service_id')::uuid and active;
ts:=(p->>'starts_at')::timestamptz;
select s.professional_id into pro from app_private.slots(t,sv.id,nullif(p->>'professional_id','')::uuid,(ts at time zone 'America/Sao_Paulo')::date) s where s.starts_at=ts limit 1;
if pro is null then raise exception 'Horário indisponível. Escolha outro horário.';end if;
insert into public.customers(tenant_id,name,phone) values(t,trim(p->>'name'),p->>'phone') on conflict(tenant_id,phone) do update set phone=excluded.phone returning id into cid;
insert into public.appointments(tenant_id,professional_id,service_id,customer_id,starts_at,ends_at,price) values(t,pro,sv.id,cid,ts,ts+make_interval(mins=>sv.duration),sv.price) returning id into aid;
insert into public.audit_logs(tenant_id,action) values(t,'Agendamento público criado');
return (select jsonb_build_object('protocol',a.protocol,'starts_at',a.starts_at,'price',a.price,'professional',(select name from public.professionals where id=pro)) from public.appointments a where a.id=aid);
end if;
if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
if op='session' then return jsonb_build_object('master',app_private.master(),'tenants',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.name,'slug',e.slug,'role',m.role)) from public.memberships m join public.tenants e on e.id=m.tenant_id join auth.users u on u.id=auth.uid() where m.active and (m.user_id=u.id or lower(m.email)=lower(u.email))),'[]'));end if;
if op='master_data' then
if not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
return jsonb_build_object('tenants',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('license',to_jsonb(l),'appointments',(select count(*) from public.appointments a where a.tenant_id=e.id))) from public.tenants e join public.licenses l on l.tenant_id=e.id),'[]'),'plans',(select jsonb_agg(to_jsonb(pl)) from public.plans pl),'audit',coalesce((select jsonb_agg(to_jsonb(q)) from (select * from public.audit_logs order by id desc limit 30) q),'[]'));end if;
if op in ('create_tenant','license','plan') then
if not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
if op='create_tenant' then
insert into public.tenants(name,slug,responsible,email,phone) values(p->>'name',p->>'slug',p->>'responsible',lower(p->>'email'),coalesce(p->>'phone','')) returning id into t;
insert into public.settings(tenant_id) values(t);
insert into public.licenses(tenant_id,plan_id,starts_on,expires_on,amount,paid) values(t,(p->>'plan_id')::uuid,(p->>'starts_on')::date,(p->>'expires_on')::date,(p->>'amount')::numeric,coalesce((p->>'paid')::boolean,false));
insert into public.memberships(tenant_id,email,role) values(t,lower(p->>'email'),'admin');
elsif op='license' then t:=(p->>'tenant_id')::uuid;update public.tenants set status=p->>'status',name=coalesce(nullif(p->>'name',''),name) where id=t;update public.licenses set expires_on=(p->>'expires_on')::date,paid=(p->>'paid')::boolean,amount=(p->>'amount')::numeric where tenant_id=t;
else insert into public.plans(id,name,amount,months) values(coalesce(nullif(p->>'id','')::uuid,gen_random_uuid()),p->>'name',(p->>'amount')::numeric,(p->>'months')::int) on conflict(id) do update set name=excluded.name,amount=excluded.amount,months=excluded.months;end if;
insert into public.audit_logs(tenant_id,actor,action) values(t,auth.uid(),op);return '{"ok":true}';end if;
t:=(p->>'tenant_id')::uuid; role_name:=app_private.role(t);
if role_name is null and not app_private.master() then raise exception 'Acesso negado ou licença inativa.';end if;
if op='workspace' then
return jsonb_build_object('tenant',(select to_jsonb(e) from public.tenants e where id=t),'settings',(select data from public.settings where tenant_id=t),'services',coalesce((select jsonb_agg(to_jsonb(s)) from public.services s where tenant_id=t),'[]'),'professionals',coalesce((select jsonb_agg(to_jsonb(s)) from public.professionals s where tenant_id=t),'[]'),'customers',coalesce((select jsonb_agg(to_jsonb(c)) from public.customers c where tenant_id=t and (role_name='admin' or app_private.master() or exists(select 1 from public.appointments a where a.customer_id=c.id and a.professional_id=app_private.own_prof(t)))),'[]'),'appointments',coalesce((select jsonb_agg(to_jsonb(a) order by starts_at) from public.appointments a where tenant_id=t and (role_name='admin' or app_private.master() or professional_id=app_private.own_prof(t))),'[]'),'memberships',case when role_name='admin' or app_private.master() then coalesce((select jsonb_agg(to_jsonb(m)) from public.memberships m where tenant_id=t),'[]') else '[]' end);
end if;
if op='status' then
update public.appointments set status=p->>'status' where id=(p->>'id')::uuid and tenant_id=t and (role_name='admin' or app_private.master() or professional_id=app_private.own_prof(t));
else
if role_name is distinct from 'admin' and not app_private.master() then raise exception 'Permissão de administrador necessária.';end if;
if op='settings' then
if (p->'data'->>'min_notice')::int not between 0 and 10080 or (p->'data'->>'max_days')::int not between 1 and 365 or (p->'data'->>'interval')::int not between 5 and 120 then raise exception 'Revise antecedência, prazo máximo (1 a 365 dias) e intervalo (5 a 120 minutos).';end if;
if (p->'data'->>'closing')::time <= (p->'data'->>'opening')::time then raise exception 'O fechamento deve ser após a abertura.';end if;
update public.settings set data=p->'data' where tenant_id=t;
elsif op='member' then
if nullif(p->>'professional_id','') is not null and not exists(select 1 from public.professionals where tenant_id=t and id=(p->>'professional_id')::uuid) then raise exception 'Profissional inválido.';end if;
insert into public.memberships(tenant_id,email,role,professional_id,active) values(t,lower(p->>'email'),p->>'role',nullif(p->>'professional_id','')::uuid,coalesce((p->>'active')::boolean,true)) on conflict(tenant_id,email) do update set role=excluded.role,professional_id=excluded.professional_id,active=excluded.active;
elsif op='service' then
insert into public.services(id,tenant_id,name,duration,price,emoji,active) values(coalesce(nullif(p->>'id','')::uuid,gen_random_uuid()),t,p->>'name',(p->>'duration')::int,(p->>'price')::numeric,p->>'emoji',coalesce((p->>'active')::boolean,true)) on conflict(id) do update set name=excluded.name,duration=excluded.duration,price=excluded.price,emoji=excluded.emoji,active=excluded.active where public.services.tenant_id=t;
elsif op='professional' then
if exists(select 1 from jsonb_array_elements_text(p->'service_ids') x where not exists(select 1 from public.services s where s.tenant_id=t and s.id=x.value::uuid)) then raise exception 'Procedimento não pertence a esta empresa.';end if;
insert into public.professionals(id,tenant_id,name,phone,photo,active,schedule,service_ids) values(coalesce(nullif(p->>'id','')::uuid,gen_random_uuid()),t,p->>'name',coalesce(p->>'phone',''),coalesce(p->>'photo',''),coalesce((p->>'active')::boolean,true),coalesce(p->'schedule','{}'),array(select jsonb_array_elements_text(p->'service_ids')::uuid)) on conflict(id) do update set name=excluded.name,phone=excluded.phone,photo=excluded.photo,active=excluded.active,schedule=excluded.schedule,service_ids=excluded.service_ids where public.professionals.tenant_id=t;
elsif op='customer' then
insert into public.customers(id,tenant_id,name,phone,birthday,notes) values(coalesce(nullif(p->>'id','')::uuid,gen_random_uuid()),t,p->>'name',regexp_replace(p->>'phone','\D','','g'),nullif(p->>'birthday','')::date,coalesce(p->>'notes','')) on conflict(id) do update set name=excluded.name,phone=excluded.phone,birthday=excluded.birthday,notes=excluded.notes where public.customers.tenant_id=t;
elsif op='appointment' then
pro:=(p->>'professional_id')::uuid;ts:=(p->>'starts_at')::timestamptz;aid:=nullif(p->>'id','')::uuid;
if p->>'status'='Bloqueado' then
insert into public.appointments(tenant_id,professional_id,starts_at,ends_at,status,notes) values(t,pro,ts,(p->>'ends_at')::timestamptz,'Bloqueado',coalesce(p->>'notes',''));
else
select * into sv from public.services where id=(p->>'service_id')::uuid and tenant_id=t and active;if not found then raise exception 'Serviço inválido.';end if;
-- Temporarily cancel the current appointment inside the transaction to validate its replacement.
if aid is not null then update public.appointments set status='Cancelado' where id=aid and tenant_id=t;end if;
if not exists(select 1 from app_private.slots(t,sv.id,pro,(ts at time zone 'America/Sao_Paulo')::date) s where s.starts_at=ts) then raise exception 'Horário indisponível ou fora do expediente.';end if;
insert into public.appointments(id,tenant_id,professional_id,service_id,customer_id,starts_at,ends_at,price,status) values(coalesce(aid,gen_random_uuid()),t,pro,sv.id,(p->>'customer_id')::uuid,ts,ts+make_interval(mins=>sv.duration),sv.price,coalesce(p->>'status','Agendado')) on conflict(id) do update set professional_id=excluded.professional_id,service_id=excluded.service_id,customer_id=excluded.customer_id,starts_at=excluded.starts_at,ends_at=excluded.ends_at,price=excluded.price,status=excluded.status where public.appointments.tenant_id=t;
end if;
else raise exception 'Operação desconhecida.';end if;end if;
insert into public.audit_logs(tenant_id,actor,action) values(t,auth.uid(),op);return '{"ok":true}';
exception when exclusion_violation then raise exception 'Este horário acabou de ser reservado. Escolha outro.'; when unique_violation then raise exception 'Já existe um cadastro com esse link ou telefone.';
end $$;
revoke all on all functions in schema app_private from public,anon,authenticated;
create function public.agenda_api(op text,p jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.gateway(op,p)$$;
-- Only the validated gateway is reachable; private helpers and secret tables stay revoked.
grant usage on schema app_private to anon,authenticated;
grant execute on function app_private.gateway(text,jsonb) to anon,authenticated;
revoke all on function public.agenda_api(text,jsonb) from public;
grant execute on function public.agenda_api(text,jsonb) to anon,authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('branding','branding',true,2097152,array['image/png','image/jpeg']);
create function public.can_brand(path text) returns boolean language sql stable security definer set search_path='' as $$select app_private.master() or app_private.role(split_part(path,'/',1)::uuid)='admin'$$;
revoke all on function public.can_brand(text) from public,anon;grant execute on function public.can_brand(text) to authenticated;
create policy branding_insert on storage.objects for insert to authenticated with check(bucket_id='branding' and public.can_brand(name));
create policy branding_update on storage.objects for update to authenticated using(bucket_id='branding' and public.can_brand(name)) with check(bucket_id='branding' and public.can_brand(name));
create policy branding_select on storage.objects for select to authenticated using(bucket_id='branding' and public.can_brand(name));
create policy branding_delete on storage.objects for delete to authenticated using(bucket_id='branding' and public.can_brand(name));

-- Security hardening and covering indexes applied on the hosted project.
create schema if not exists extensions;
alter extension btree_gist set schema extensions;
create function app_private.can_brand(path text) returns boolean language sql stable security definer set search_path='' as $$select app_private.master() or app_private.role(split_part(path,'/',1)::uuid)='admin'$$;
revoke all on function app_private.can_brand(text) from public,anon;
grant execute on function app_private.can_brand(text) to authenticated;
create or replace function public.can_brand(path text) returns boolean language sql stable security invoker set search_path='' as $$select app_private.can_brand(path)$$;
create index on public.appointments(tenant_id,customer_id);
create index on public.appointments(tenant_id,service_id);
