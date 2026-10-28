-- Complete application data recovery. Only the authenticated Edge service may call
-- these functions; the Edge independently validates the current Master session.
create table app_private.recovery_previews(id uuid primary key default gen_random_uuid(),actor uuid not null,archive_hash text not null,expires_at timestamptz not null default now()+interval '15 minutes',used_at timestamptz);
alter table app_private.recovery_previews enable row level security;
revoke all on app_private.recovery_previews from public,anon,authenticated;

create function app_private.recovery_gate(actor uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' or actor is null or not exists(select 1 from public.platform_admins m join auth.users u on u.id=m.user_id where m.user_id=actor and u.email_confirmed_at is not null and u.deleted_at is null and (u.banned_until is null or u.banned_until<now())) then raise exception 'Acesso exclusivo Master.';end if;
end $$;
create function app_private.recovery_access() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and app_private.master()$$;
revoke all on function app_private.recovery_access() from public,anon;
grant execute on function app_private.recovery_access() to authenticated;
create function public.agenda_recovery_access() returns boolean language sql stable security invoker set search_path='' as $$select app_private.recovery_access()$$;
revoke all on function public.agenda_recovery_access() from public,anon;
grant execute on function public.agenda_recovery_access() to authenticated;

create function app_private.recovery_snapshot(actor uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tab text;tables jsonb:='{}';part jsonb;result jsonb;allowed text[]:=array['platform_admins','plans','tenants','licenses','services','professionals','memberships','settings','customers','appointments','whatsapp_templates','financial_entries','audit_logs'];
begin
 perform app_private.recovery_gate(actor);
 if exists(select 1 from auth.mfa_factors) or exists(select 1 from auth.identities where provider<>'email') then raise exception 'Use o backup PostgreSQL para contas com MFA ou provedores externos.';end if;
 if exists(select 1 from pg_tables where schemaname='public' and not (tablename=any(allowed)) and tablename<>'push_subscriptions') then raise exception 'O esquema possui novas tabelas. Atualize o formato de backup antes de exportar.';end if;
 foreach tab in array allowed loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',tab) into part;
  tables:=tables||jsonb_build_object(tab,part);
 end loop;
 select jsonb_build_object('format','agenda-complete-data','version',1,'exported_at',now(),'tables',tables,
 'accounts',coalesce((select jsonb_agg(to_jsonb(u)-array['confirmed_at','confirmation_token','recovery_token','email_change_token_new','email_change_token_current','reauthentication_token','phone_change_token','email_change','phone_change']) from auth.users u),'[]'::jsonb),
 'identities',coalesce((select jsonb_agg(to_jsonb(i)-'email') from auth.identities i),'[]'::jsonb),
 'objects',coalesce((select jsonb_agg(jsonb_build_object('bucket',bucket_id,'path',name,'updated_at',updated_at,'size',metadata->'size','mime',metadata->>'mimetype') order by bucket_id,name) from storage.objects),'[]'::jsonb)) into result;
 if octet_length(result::text)>8388608 then raise exception 'Os dados excedem 8 MB. Nenhum backup parcial foi gerado; utilize o procedimento PostgreSQL para bases maiores.';end if;
 return result;
end $$;

-- Preserve existing records; insert missing records in dependency order. Preview
-- exercises the actual constraints inside a rolled-back subtransaction.
create function app_private.recovery_merge(actor uuid,doc jsonb,apply boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare tab text;sch text;keycol text;cols text;part jsonb;item jsonb;old jsonb;counts jsonb:='{}';total int;missing int;different int;inserted int;allowed text[]:=array['users','identities','platform_admins','plans','tenants','licenses','services','professionals','memberships','settings','customers','appointments','whatsapp_templates','financial_entries','audit_logs'];
begin
 perform app_private.recovery_gate(actor);
 if doc->>'format' is distinct from 'agenda-complete-data' or doc->>'version' is distinct from '1' or jsonb_typeof(doc->'tables') is distinct from 'object' or octet_length(doc::text)>8388608 then raise exception 'Formato ou tamanho de backup inválido.';end if;
 -- Lock all affected tables in the same order to prevent changes during validation
 -- and to serialize a restore against live writes. The transaction stays short.
 lock table auth.users,auth.identities,public.platform_admins,public.plans,public.tenants,public.licenses,public.services,public.professionals,public.memberships,public.settings,public.customers,public.appointments,public.whatsapp_templates,public.financial_entries,public.audit_logs in share row exclusive mode;
 begin
  perform set_config('agenda.restoring','on',true);
  foreach tab in array allowed loop
   sch:=case when tab in ('users','identities') then 'auth' else 'public' end;
   keycol:=case when tab='platform_admins' then 'user_id' when tab in ('settings','whatsapp_templates') then 'tenant_id' else 'id' end;
   part:=case when tab='users' then doc->'accounts' when tab='identities' then doc->'identities' else doc->'tables'->tab end;
   if jsonb_typeof(part) is distinct from 'array' or jsonb_array_length(part)>100000 then raise exception 'Tabela ausente ou inválida: %.',tab;end if;
   total:=jsonb_array_length(part);missing:=0;different:=0;inserted:=0;
   if exists(select 1 from jsonb_array_elements(part) r where jsonb_typeof(r)<>'object' or nullif(r->>keycol,'') is null) or (select count(distinct r->>keycol) from jsonb_array_elements(part) r)<>total then raise exception 'Identificadores inválidos ou duplicados: %.',tab;end if;
   select string_agg(quote_ident(c.column_name),',' order by c.ordinal_position) into cols from information_schema.columns c where c.table_schema=sch and c.table_name=tab and c.is_generated='NEVER';
   for item in select value from jsonb_array_elements(part) loop
    execute format('select to_jsonb(t) from %I.%I t where %I::text=$1',sch,tab,keycol) into old using item->>keycol;
    if old is not null then
     if old ? 'tenant_id' and old->>'tenant_id' is distinct from item->>'tenant_id' then raise exception 'Conflito entre empresas em %. Restauração interrompida.',tab;end if;
     if old @> item is not true then different:=different+1;end if;
     continue;
    end if;
    missing:=missing+1;
    if tab='users' then
     if item->>'role' is distinct from 'authenticated' or coalesce((item->>'is_super_admin')::boolean,false) or coalesce((item->>'is_sso_user')::boolean,false) or coalesce((item->>'is_anonymous')::boolean,false) then raise exception 'Tipo de conta não suportado pelo restaurador.';end if;
     item:=item||jsonb_build_object('confirmation_token','','recovery_token','','email_change_token_new','','email_change_token_current','','reauthentication_token','','phone_change_token','','email_change','','phone_change','');
    end if;
    execute format('insert into %I.%I(%s) overriding system value select %s from jsonb_populate_record(null::%I.%I,$1)',sch,tab,cols,cols,sch,tab) using item;
    inserted:=inserted+1;
   end loop;
   counts:=counts||jsonb_build_object(tab,jsonb_build_object('backup',total,'missing',missing,'preserved',total-missing,'different',different,'inserted',inserted));
  end loop;
  -- Extra references stored as arrays or non-FK columns must remain tenant scoped.
  if exists(select 1 from public.professionals p cross join lateral unnest(p.service_ids) sid where not exists(select 1 from public.services s where s.id=sid and s.tenant_id=p.tenant_id)) or exists(select 1 from public.memberships m where m.professional_id is not null and not exists(select 1 from public.professionals p where p.id=m.professional_id and p.tenant_id=m.tenant_id)) or exists(select 1 from public.financial_entries f join public.appointments a on a.id=f.appointment_id where a.tenant_id<>f.tenant_id) then raise exception 'Vínculos de empresa inconsistentes. Nenhum registro restaurado.';end if;
  if not apply then raise exception using errcode='ZB001',message='preview rollback';end if;
 exception when sqlstate 'ZB001' then null;
 end;
 perform set_config('agenda.restoring','off',true);
 return counts;
end $$;
create function public.agenda_recovery_service(op text,actor uuid,p jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;ticket app_private.recovery_previews;newid uuid;
begin
 perform app_private.recovery_gate(actor);
 if op='export' then return app_private.recovery_snapshot(actor);end if;
 if op='preview' then
  result:=app_private.recovery_merge(actor,p->'data',false);
  delete from app_private.recovery_previews where expires_at<now();
  insert into app_private.recovery_previews(actor,archive_hash) values(actor,p->>'archive_hash') returning id into newid;
  return jsonb_build_object('ticket',newid,'counts',result,'expires_minutes',15);
 elsif op in ('authorize','restore') then
  select * into ticket from app_private.recovery_previews where id=(p->>'ticket')::uuid for update;
  if ticket.id is null or ticket.actor<>actor or ticket.used_at is not null or ticket.expires_at<now() or ticket.archive_hash is distinct from p->>'archive_hash' then raise exception 'Prévia expirada ou arquivo alterado. Valide novamente.';end if;
  if op='authorize' then return jsonb_build_object('ok',true);end if;
  if p->>'confirmation' is distinct from 'RESTAURAR' then raise exception 'Confirme a restauração.';end if;
  result:=app_private.recovery_merge(actor,p->'data',true);
  update app_private.recovery_previews set used_at=now() where id=ticket.id;
  perform setval(pg_get_serial_sequence('public.audit_logs','id'),greatest(1,(select coalesce(max(id),0)+1 from public.audit_logs)),false);
  insert into public.audit_logs(actor,action) values(actor,'backup_restore_completed');
  return jsonb_build_object('ok',true,'counts',result);
 end if;
 raise exception 'Operação inválida.';
end $$;
revoke all on function public.agenda_recovery_service(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.agenda_recovery_service(text,uuid,jsonb) to service_role;
revoke all on function app_private.recovery_gate(uuid),app_private.recovery_snapshot(uuid),app_private.recovery_merge(uuid,jsonb,boolean) from public,anon,authenticated;

-- Restoring old appointments must never notify customers or devices again.
create or replace function app_private.enqueue_booking_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if current_setting('agenda.restoring',true)='on' then return new;end if;
 if new.status not in ('Agendado','Confirmado','Concluído') or new.customer_id is null then return new;end if;
 insert into app_private.push_deliveries(subscription_id,appointment_id)
 select s.id,new.id from public.push_subscriptions s where s.tenant_id=new.tenant_id and s.active and app_private.push_recipient(s.tenant_id,s.user_id,new.professional_id)
 on conflict(subscription_id,appointment_id) do nothing;
 perform app_private.kick_push();return new;
end $$;
