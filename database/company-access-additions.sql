-- Account credentials are handled only by Supabase Auth; this RPC never receives a password.
create or replace function app_private.company_access(op text,p jsonb,request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 account_id uuid;metadata jsonb;tid uuid;actual_request uuid:=request_id;
 mail text:=lower(btrim(p->>'email'));company_slug text:=p->>'slug';price numeric;starts date;expires date;
begin
 if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
 if op not in ('prepare','finish') or request_id is null then raise exception 'Solicitação inválida.';end if;
 if p ?| array['password','confirmPassword','initial_password','confirm_password'] then raise exception 'Credenciais não devem ser enviadas ao banco de negócio.';end if;
 if mail is null or length(mail)>254 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Informe um e-mail de acesso válido.';end if;
 if nullif(btrim(p->>'name'),'') is null or length(p->>'name')>120 or nullif(btrim(p->>'responsible'),'') is null or length(p->>'responsible')>120 then raise exception 'Informe o estabelecimento e o responsável (até 120 caracteres).';end if;
 if company_slug is null or company_slug !~ '^[a-z][a-z0-9-]{2,49}$' or company_slug in ('master','admin','api','signin-with-chatgpt','signout-with-chatgpt','callback','privacidade','termos','manifest','demo','favicon','assets','_next') then raise exception 'Escolha um link válido e não reservado.';end if;
 if not app_private.valid_document(p->>'document_type',p->>'document_number') then raise exception 'Informe um CPF ou CNPJ válido.';end if;
 if not exists(select 1 from public.plans where id=(p->>'plan_id')::uuid and active and deleted_at is null) then raise exception 'Selecione um plano disponível.';end if;
 starts:=(p->>'starts_on')::date;expires:=(p->>'expires_on')::date;price:=(p->>'amount')::numeric;
 if starts is null or expires is null or expires<starts then raise exception 'Informe início e vencimento válidos.';end if;
 if price is null or price<0 or price>99999999.99 or price::text in ('NaN','Infinity','-Infinity') or price<>round(price,2) then raise exception 'Informe um valor válido para a licença.';end if;
 perform pg_advisory_xact_lock(hashtextextended('agenda-company:'||company_slug,0));
 select id,raw_app_meta_data into account_id,metadata from auth.users where lower(email)=mail;
 if account_id is not null then
  if metadata->>'agenda_company_actor' is distinct from auth.uid()::text or metadata->>'agenda_company_slug' is distinct from company_slug or metadata->>'agenda_company_request' is null then
   raise exception 'Este e-mail já possui uma conta. Use outro e-mail para o novo acesso; a senha existente não será alterada.';
  end if;
  actual_request:=(metadata->>'agenda_company_request')::uuid;
 end if;
 select id into tid from public.tenants where public.tenants.slug=company_slug;
 if tid is not null then
  if account_id is not null and exists(select 1 from public.memberships where tenant_id=tid and user_id=account_id and email=mail and role='admin' and active) then
   return jsonb_build_object('ok',true,'complete',true,'tenant_id',tid,'user_id',account_id,'request_id',actual_request);
  end if;
  raise exception 'Este link já está em uso.';
 end if;
 if op='prepare' then return jsonb_build_object('ok',true,'complete',false,'user_id',account_id,'request_id',actual_request);end if;
 if account_id is null or not exists(select 1 from auth.users where id=account_id and email_confirmed_at is not null) then raise exception 'O acesso inicial ainda não foi criado. Tente novamente.';end if;
 perform app_private.company_save('create_tenant',p||jsonb_build_object('email',mail));
 select id into tid from public.tenants where public.tenants.slug=company_slug;
 update public.memberships set user_id=account_id where tenant_id=tid and email=mail and role='admin';
 insert into public.audit_logs(tenant_id,actor,action) values(tid,auth.uid(),'Acesso inicial por e-mail e senha provisionado');
 return jsonb_build_object('ok',true,'complete',true,'tenant_id',tid,'user_id',account_id,'request_id',actual_request);
end $$;
revoke all on function app_private.company_access(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function app_private.company_access(text,jsonb,uuid) to authenticated;
create function public.agenda_company_access(op text,p jsonb,request_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select app_private.company_access(op,p,request_id)$$;
revoke all on function public.agenda_company_access(text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.agenda_company_access(text,jsonb,uuid) to authenticated;
