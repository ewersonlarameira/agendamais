-- Professional access is consultation-only and bound to a stable professional ID.
create or replace function app_private.role(t uuid) returns text language sql stable security definer set search_path='' as $$
 select m.role from public.memberships m join public.tenants e on e.id=m.tenant_id join public.licenses l on l.tenant_id=e.id join auth.users u on u.id=auth.uid()
 where m.tenant_id=t and m.active and e.status='active' and l.starts_on<=(now() at time zone 'America/Sao_Paulo')::date and l.expires_on>=(now() at time zone 'America/Sao_Paulo')::date
 and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<now())
 and (m.user_id=u.id or (m.user_id is null and lower(m.email)=lower(u.email)))
 and (m.role='admin' or exists(select 1 from public.professionals pr where pr.id=m.professional_id and pr.tenant_id=t and pr.active))
 order by case when m.role='admin' then 0 else 1 end,m.id limit 1
$$;
create or replace function app_private.own_prof(t uuid) returns uuid language sql stable security definer set search_path='' as $$
 select m.professional_id from public.memberships m join auth.users u on u.id=auth.uid() join public.professionals p on p.id=m.professional_id and p.tenant_id=m.tenant_id
 where m.tenant_id=t and m.active and m.role='professional' and p.active and (m.user_id=u.id or (m.user_id is null and lower(m.email)=lower(u.email))) order by m.id limit 1
$$;

create function app_private.professional_schedule(p jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tid uuid;pid uuid;first_day date;last_day date;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta de profissional.';end if;
 tid:=(p->>'tenant_id')::uuid;
 if app_private.role(tid) is distinct from 'professional' then raise exception 'Acesso profissional indisponível para esta empresa ou licença inativa.';end if;
 pid:=app_private.own_prof(tid);
 if pid is null then raise exception 'Nenhum profissional ativo vinculado ao seu acesso.';end if;
 first_day:=(p->>'from')::date;last_day:=(p->>'to')::date;
 if first_day is null or last_day is null or last_day<first_day or last_day-first_day>92 then raise exception 'Selecione um período de até 93 dias.';end if;
 return jsonb_build_object(
 'tenant',(select jsonb_build_object('id',id,'name',name,'slug',slug) from public.tenants where id=tid),
 'professional',(select jsonb_build_object('id',id,'name',name,'photo',photo) from public.professionals where id=pid and tenant_id=tid),
 'settings',(select jsonb_build_object('palette',data->>'palette','accent',data->>'accent','logo',data->>'logo','display_name',data->>'display_name') from public.settings where tenant_id=tid),
 'appointments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'professional_id',a.professional_id,'starts_at',a.starts_at,'ends_at',a.ends_at,'status',a.status,'customer',c.name,'procedure',s.name,'emoji',s.emoji) order by a.starts_at,a.id)
 from public.appointments a left join public.customers c on c.id=a.customer_id and c.tenant_id=tid left join public.services s on s.id=a.service_id and s.tenant_id=tid
 where a.tenant_id=tid and a.professional_id=pid and a.starts_at>=first_day::timestamp at time zone 'America/Sao_Paulo' and a.starts_at<(last_day+1)::timestamp at time zone 'America/Sao_Paulo'),'[]'::jsonb));
end $$;
revoke all on function app_private.professional_schedule(jsonb) from public,anon;
grant execute on function app_private.professional_schedule(jsonb) to authenticated;
create function public.agenda_professional_schedule(p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.professional_schedule(p)$$;
revoke all on function public.agenda_professional_schedule(jsonb) from public,anon;
grant execute on function public.agenda_professional_schedule(jsonb) to authenticated;

create function app_private.professional_access(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid;pid uuid;mail text;m public.memberships;uid uuid;meta jsonb;company public.tenants;accounts int;
begin
 if auth.uid() is null then raise exception 'Entre na conta do administrador.';end if;
 if p ?| array['password','initial_password','confirm_password','new_password'] then raise exception 'Senhas não devem entrar no banco de negócio.';end if;
 tid:=(p->>'tenant_id')::uuid;pid:=(p->>'professional_id')::uuid;
 if app_private.role(tid) is distinct from 'admin' and not app_private.master() then raise exception 'Permissão de administrador necessária.';end if;
 select * into company from public.tenants where id=tid for update;
 if not found then raise exception 'Empresa não encontrada.';end if;
 perform 1 from public.professionals where id=pid and tenant_id=tid and active for update;
 if not found then raise exception 'Selecione um profissional ativo deste estabelecimento.';end if;
 mail:=lower(btrim(p->>'email'));
 if mail is null or length(mail)>254 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Informe um e-mail de login válido.';end if;
 select count(*) into accounts from public.memberships where tenant_id=tid and professional_id=pid and role='professional';
 if accounts>1 then raise exception 'Este profissional possui vários acessos. Revise-os em Configurações → Acessos.';end if;
 select * into m from public.memberships where tenant_id=tid and professional_id=pid and role='professional' for update;
 if m.id is not null and lower(m.email)<>mail then raise exception 'O profissional já possui outro login. Edite-o pelo Master.';end if;
 if exists(select 1 from public.memberships where tenant_id=tid and lower(email)=mail and id is distinct from m.id) then raise exception 'Este e-mail já possui outra permissão nesta empresa.';end if;
 select id,raw_app_meta_data into uid,meta from auth.users where lower(email)=mail;
 if uid is not null then
  if exists(select 1 from public.platform_admins where user_id=uid) or exists(select 1 from public.memberships where (user_id=uid or lower(email)=mail) and (tenant_id<>tid or role<>'professional' or professional_id is distinct from pid)) then raise exception 'Este e-mail já possui outra conta. Use um login exclusivo para o profissional.';end if;
  if m.user_id is distinct from uid and (meta->>'agenda_professional_actor' is distinct from auth.uid()::text or meta->>'agenda_professional_id' is distinct from pid::text or meta->>'agenda_professional_tenant' is distinct from tid::text) then raise exception 'Este e-mail já está em uso. Nenhuma senha existente será alterada.';end if;
  if not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and deleted_at is null and (banned_until is null or banned_until<now())) then raise exception 'Conta de acesso indisponível.';end if;
 end if;
 if op='prepare' then return jsonb_build_object('user_id',uid,'complete',m.user_id=uid and m.active,'slug',company.slug);end if;
 if op<>'finish' then raise exception 'Operação inválida.';end if;
 if uid is null or uid is distinct from (p->>'account_id')::uuid then raise exception 'Não foi possível confirmar o acesso. Repita com o mesmo e-mail.';end if;
 if m.id is null then
  insert into public.memberships(tenant_id,email,user_id,role,professional_id,active) values(tid,mail,uid,'professional',pid,true);
 else
  update public.memberships set user_id=uid,active=true where id=m.id;
 end if;
 insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'Acesso de consulta à própria agenda criado para profissional: '||pid::text);
 return jsonb_build_object('ok',true,'slug',company.slug,'email',mail);
end $$;
revoke all on function app_private.professional_access(text,jsonb) from public,anon;
grant execute on function app_private.professional_access(text,jsonb) to authenticated;
create function public.agenda_professional_access(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.professional_access(op,p)$$;
revoke all on function public.agenda_professional_access(text,jsonb) from public,anon;
grant execute on function public.agenda_professional_access(text,jsonb) to authenticated;

-- Harden legacy endpoints as well: changing the URL must not restore old powers.
do $$declare definition text;begin
 select pg_get_functiondef('app_private.gateway(text,jsonb)'::regprocedure) into definition;
 if position('Acesso profissional permite somente consultar a própria agenda.' in definition)=0 then
  definition:=replace(definition,'if op=''workspace'' then',E'if role_name=''professional'' then raise exception ''Acesso profissional permite somente consultar a própria agenda.'';end if;\nif op=''workspace'' then');
  execute definition;
 end if;
 select pg_get_functiondef('app_private.appointment_save(text,jsonb)'::regprocedure) into definition;
 if position('Acesso profissional é somente leitura.' in definition)=0 then
  definition:=replace(definition,'if op=''appointment'' then',E'if rol=''professional'' then raise exception ''Acesso profissional é somente leitura.'';end if;\nif op=''appointment'' then');
  execute definition;
 end if;
 select pg_get_functiondef('app_private.message_templates(text,jsonb)'::regprocedure) into definition;
 -- The former professional workspace also loaded internal WhatsApp templates.
 definition:=regexp_replace(definition,'begin',E'begin\n if app_private.role((p->>''tenant_id'')::uuid)=''professional'' then raise exception ''Permissão de administrador necessária.'';end if;', 'i');
 execute definition;
end $$;
