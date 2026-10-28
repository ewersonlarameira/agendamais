-- Scoped Master management. Auth secrets/passwords never enter these RPCs.
create function app_private.master_company(op text,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 tid uuid;company public.tenants;lic public.licenses;member public.memberships;
 uid uuid;other_uid uuid;mail text;old_mail text;metadata jsonb;revision text;doc text;kind text;
begin
 if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
 if p ?| array['password','confirm_password','new_password','initial_password'] then raise exception 'Credenciais não devem entrar no banco de negócio.';end if;
 tid:=(p->>'tenant_id')::uuid;
 select * into company from public.tenants where id=tid for update;
 if not found then raise exception 'Empresa não encontrada.';end if;
 select * into lic from public.licenses where tenant_id=tid for update;
 revision:=md5((to_jsonb(company)||to_jsonb(lic))::text);
 if op='get' then
  return jsonb_build_object('tenant',to_jsonb(company),'license',to_jsonb(lic),'revision',revision,
   'current_plan',(select to_jsonb(pl) from public.plans pl where id=lic.plan_id),
   'settings',(select data from public.settings where tenant_id=tid),
   'professionals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active)) from public.professionals where tenant_id=tid),'[]'),
   'members',coalesce((select jsonb_agg(to_jsonb(m)||jsonb_build_object('revision',md5(to_jsonb(m)::text),'account_id',u.id,'login_email',u.email,'has_account',u.id is not null,'protected_account',exists(select 1 from public.platform_admins where user_id=u.id),'shared_account',exists(select 1 from public.memberships elsewhere where elsewhere.tenant_id<>tid and (elsewhere.user_id=u.id or lower(elsewhere.email)=lower(u.email))))) from public.memberships m left join auth.users u on u.id=m.user_id or (m.user_id is null and lower(u.email)=lower(m.email)) where m.tenant_id=tid),'[]'));
 end if;
 if op='save' then
  if p->>'revision' is distinct from revision then raise exception 'Os dados foram alterados. Reabra o editor para carregar a versão atual.';end if;
  if nullif(btrim(p->>'name'),'') is null or length(p->>'name')>120 or nullif(btrim(p->>'responsible'),'') is null or length(p->>'responsible')>120 then raise exception 'Informe nome e responsável com até 120 caracteres.';end if;
  mail:=lower(btrim(p->>'email'));
  if mail is null or length(mail)>254 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Informe um e-mail comercial válido.';end if;
  if (p->>'slug') is null or (p->>'slug') !~ '^[a-z][a-z0-9-]{2,49}$' or p->>'slug' in ('master','admin','api','signin-with-chatgpt','signout-with-chatgpt','callback','privacidade','termos','manifest','demo','favicon','assets','_next') then raise exception 'Informe um link válido e não reservado.';end if;
  if exists(select 1 from public.tenants where slug=p->>'slug' and id<>tid) then raise exception 'Este link já está em uso.';end if;
  kind:=nullif(p->>'document_type','');doc:=upper(regexp_replace(coalesce(p->>'document_number',''),'[^A-Za-z0-9]','','g'));
  if doc<>'' and not app_private.valid_document(kind,doc) then raise exception 'Informe um CPF ou CNPJ válido.';end if;
  if (p->>'plan_id')::uuid is distinct from lic.plan_id and not exists(select 1 from public.plans where id=(p->>'plan_id')::uuid and active and deleted_at is null) then raise exception 'Selecione um plano disponível.';end if;
  if nullif(p->>'plan_id','') is null or nullif(p->>'starts_on','') is null or nullif(p->>'expires_on','') is null or (p->>'expires_on')::date<(p->>'starts_on')::date then raise exception 'Revise o plano e as datas da licença.';end if;
  if (p->>'amount') is null or (p->>'amount')::numeric<0 or (p->>'amount')::numeric>99999999.99 or (p->>'amount')::numeric::text in ('NaN','Infinity','-Infinity') or (p->>'amount')::numeric<>round((p->>'amount')::numeric,2) then raise exception 'Informe um valor válido para a assinatura.';end if;
  if coalesce(p->>'status','') not in ('active','suspended') then raise exception 'Status inválido.';end if;
  update public.tenants set name=btrim(p->>'name'),slug=p->>'slug',responsible=btrim(p->>'responsible'),email=mail,phone=coalesce(p->>'phone',''),document_type=case when doc='' then null else kind end,document_number=nullif(doc,''),status=p->>'status' where id=tid;
  update public.licenses set plan_id=(p->>'plan_id')::uuid,starts_on=(p->>'starts_on')::date,expires_on=(p->>'expires_on')::date,amount=(p->>'amount')::numeric,paid=coalesce((p->>'paid')::boolean,false) where tenant_id=tid;
  insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'Edição completa de dados e licença da empresa');
  return '{"ok":true}';
 end if;
 if op='member_save' then
  if nullif(p->>'id','') is null then
   mail:=lower(btrim(p->>'email'));
   if mail is null or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(mail)>254 then raise exception 'Informe um e-mail de login válido.';end if;
   if exists(select 1 from public.memberships where tenant_id=tid and lower(email)=mail) then raise exception 'Este e-mail já está autorizado. Edite o acesso existente.';end if;
  else
   select * into member from public.memberships where id=(p->>'id')::uuid and tenant_id=tid for update;
   if not found then raise exception 'Acesso não pertence a esta empresa.';end if;
   if p->>'revision' is distinct from md5(to_jsonb(member)::text) then raise exception 'O acesso foi alterado. Atualize o editor.';end if;
   mail:=member.email;
  end if;
  if coalesce(p->>'role','') not in ('admin','professional') then raise exception 'Permissão inválida.';end if;
  if p->>'role'='professional' and not exists(select 1 from public.professionals where id=nullif(p->>'professional_id','')::uuid and tenant_id=tid) then raise exception 'Selecione um profissional desta empresa.';end if;
  if member.id is null then
   insert into public.memberships(tenant_id,email,role,professional_id,active) values(tid,mail,p->>'role',case when p->>'role'='professional' then (p->>'professional_id')::uuid else null end,coalesce((p->>'active')::boolean,true));
  else
   update public.memberships set role=p->>'role',professional_id=case when p->>'role'='professional' then (p->>'professional_id')::uuid else null end,active=coalesce((p->>'active')::boolean,true) where id=member.id;
   if not coalesce((p->>'active')::boolean,true) then
    update public.push_subscriptions set active=false,updated_at=now() where tenant_id=tid and user_id in (select id from auth.users where id=member.user_id or lower(email)=lower(member.email));
   end if;
  end if;
  insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'Edição de permissão/acesso: '||mail);
  return '{"ok":true}';
 end if;
 if op in ('credentials_prepare','credentials_finish') then
  select * into member from public.memberships where id=(p->>'id')::uuid and tenant_id=tid for update;
  if not found then raise exception 'Acesso não pertence a esta empresa.';end if;
  if p->>'revision' is distinct from md5(to_jsonb(member)::text) then raise exception 'O acesso foi alterado. Reabra a edição de login.';end if;
  mail:=lower(btrim(p->>'email'));old_mail:=member.email;
  if mail is null or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(mail)>254 then raise exception 'Informe um e-mail de login válido.';end if;
  select id,raw_app_meta_data into uid,metadata from auth.users where id=member.user_id or (member.user_id is null and lower(email)=lower(member.email));
  if uid is null then
   select id,raw_app_meta_data into uid,metadata from auth.users where lower(email)=mail;
   if uid is not null and (metadata->>'agenda_member_actor' is distinct from auth.uid()::text or metadata->>'agenda_member_id' is distinct from member.id::text) then raise exception 'Este e-mail já possui outra conta. A senha não será alterada.';end if;
  end if;
  if uid is not null then
   if exists(select 1 from public.platform_admins where user_id=uid) then raise exception 'A conta Master não pode ser alterada pelo editor de empresas.';end if;
   if exists(select 1 from public.memberships where tenant_id<>tid and (user_id=uid or lower(email)=(select lower(email) from auth.users where id=uid))) then raise exception 'Esta conta possui acesso a outras empresas. Altere as credenciais pela própria conta ou utilize um login exclusivo.';end if;
  end if;
  if exists(select 1 from public.memberships where tenant_id=tid and id<>member.id and lower(email)=mail) then raise exception 'Este e-mail já possui outro acesso nesta empresa.';end if;
  if exists(select 1 from auth.users where lower(email)=mail and id is distinct from uid) then raise exception 'Este e-mail já possui outra conta.';end if;
  if op='credentials_prepare' then
   if uid is not null and member.user_id is null then update public.memberships set user_id=uid where id=member.id returning * into member;end if;
   return jsonb_build_object('user_id',uid,'email',mail,'member_id',member.id,'tenant_id',tid,'revision',md5(to_jsonb(member)::text));
  end if;
  if uid is null or uid is distinct from (p->>'account_id')::uuid or not exists(select 1 from auth.users where id=uid and lower(email)=mail and email_confirmed_at is not null) then raise exception 'Não foi possível confirmar o novo login. Tente novamente.';end if;
  update public.memberships set email=mail,user_id=uid where id=member.id;
  update public.push_subscriptions set active=false,updated_at=now() where tenant_id=tid and user_id=uid;
  insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'Credenciais de acesso atualizadas: '||mail);
  return '{"ok":true}';
 end if;
 raise exception 'Operação inválida.';
end $$;
revoke all on function app_private.master_company(text,jsonb) from public,anon,authenticated;
grant execute on function app_private.master_company(text,jsonb) to authenticated;
create function public.agenda_master_company(op text,p jsonb) returns jsonb
language sql security invoker set search_path='' as $$select app_private.master_company(op,p)$$;
revoke all on function public.agenda_master_company(text,jsonb) from public,anon,authenticated;
grant execute on function public.agenda_master_company(text,jsonb) to authenticated;
