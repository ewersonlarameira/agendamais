-- Web Push: tenant/user device opt-in, durable delivery queue and background dispatch.
-- VAPID keys and dispatch secret are provisioned separately in app_private.secrets.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create table public.push_subscriptions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id),
 user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null check(length(endpoint) between 20 and 2048),p256dh text not null,auth_key text not null,
 active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,user_id,endpoint)
);
create index push_subscriptions_user on public.push_subscriptions(user_id);
create index push_subscriptions_tenant_active on public.push_subscriptions(tenant_id) where active;
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from public,anon,authenticated;
create policy push_checked_rpc_only on public.push_subscriptions to authenticated using(false) with check(false);
create table app_private.push_deliveries(
 id uuid primary key default gen_random_uuid(),subscription_id uuid not null references public.push_subscriptions(id) on delete cascade,
 appointment_id uuid references public.appointments(id),event text not null default 'booking' check(event in ('booking','test')),
 state text not null default 'pending' check(state in ('pending','sent','failed','skipped')),
 attempts int not null default 0,available_at timestamptz not null default now(),lease_token uuid,
 created_at timestamptz not null default now(),finished_at timestamptz,last_status int,
 unique(subscription_id,appointment_id)
);
create index push_queue_pending on app_private.push_deliveries(available_at) where state='pending';
create index push_queue_subscription on app_private.push_deliveries(subscription_id);
create index push_queue_appointment on app_private.push_deliveries(appointment_id);
alter table app_private.push_deliveries enable row level security;
revoke all on app_private.push_deliveries from public,anon,authenticated;
create policy push_queue_service_only on app_private.push_deliveries to authenticated using(false) with check(false);

create function app_private.push_recipient(t uuid,u uuid,pro uuid default null) returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from public.memberships m join auth.users a on a.id=u join public.tenants e on e.id=m.tenant_id join public.licenses l on l.tenant_id=e.id
 where m.tenant_id=t and m.active and a.email_confirmed_at is not null and (m.user_id=u or lower(m.email)=lower(a.email)) and e.status='active'
 and (now() at time zone 'America/Sao_Paulo')::date between l.starts_on and l.expires_on
 and (m.role='admin' or (m.role='professional' and (pro is null or m.professional_id=pro))))
$$;

create or replace function app_private.kick_push() returns void language plpgsql security definer set search_path='' as $$
declare token text;origin text;stamp text:=floor(extract(epoch from clock_timestamp()))::bigint::text;nonce text:=replace(gen_random_uuid()::text,'-','');signature text;
begin
 delete from app_private.push_deliveries where created_at<now()-interval '7 days' and state<>'pending';
 update app_private.push_deliveries set state='failed',finished_at=now() where state='pending' and (attempts>=6 or created_at<now()-interval '1 day');
 if not exists(select 1 from app_private.push_deliveries where state='pending' and available_at<=now()) then return;end if;
 select value into token from app_private.secrets where key='push_dispatch';select value into origin from app_private.secrets where key='push_function_url';
 if token is null or origin is null then return;end if;
 -- pg_net transport tables have platform-managed grants. Never put a reusable secret in them.
 signature:=encode(extensions.hmac('agenda-push:'||stamp||':'||nonce||':dispatch',token,'sha256'),'hex');
 perform net.http_post(url:=origin,headers:=jsonb_build_object('Content-Type','application/json','x-agenda-push',signature,'x-agenda-timestamp',stamp,'x-agenda-nonce',nonce),body:='{}'::jsonb,timeout_milliseconds:=10000);
exception when others then
 -- Provider/dispatch outages never roll back a customer's booking. Cron retries the durable queue.
 return;
end $$;

create function app_private.enqueue_booking_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status not in ('Agendado','Confirmado','Concluído') or new.customer_id is null then return new;end if;
 insert into app_private.push_deliveries(subscription_id,appointment_id)
 select s.id,new.id from public.push_subscriptions s where s.tenant_id=new.tenant_id and s.active and app_private.push_recipient(s.tenant_id,s.user_id,new.professional_id)
 on conflict(subscription_id,appointment_id) do nothing;
 perform app_private.kick_push();return new;
end $$;
create trigger appointment_push_created after insert on public.appointments for each row execute function app_private.enqueue_booking_push();

create function app_private.push_client(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare tid uuid;ep text:=p->>'endpoint';sub jsonb:=p->'subscription';sid uuid;pub text;
begin
 if auth.uid() is null then raise exception 'Entre na sua conta.';end if;
 if op='logout' then update public.push_subscriptions set active=false,updated_at=now() where user_id=auth.uid();return '{"ok":true}';end if;
 tid:=(p->>'tenant_id')::uuid;
 if not app_private.push_recipient(tid,auth.uid()) then raise exception 'Sem permissão para notificações desta empresa ou licença inativa.';end if;
 select value into pub from app_private.secrets where key='push_vapid_public';
 if op='status' then return jsonb_build_object('publicKey',pub,'enabled',exists(select 1 from public.push_subscriptions where tenant_id=tid and user_id=auth.uid() and endpoint=ep and active));end if;
 if op='register' then
  ep:=sub->>'endpoint';
  if pub is null then raise exception 'As notificações ainda não foram configuradas.';end if;
  if length(coalesce(ep,'')) not between 20 and 2048 or ep !~ '^https://(fcm\.googleapis\.com|updates\.push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9-]+\.notify\.windows\.com)/[^[:space:]]+$'
   or coalesce(sub->'keys'->>'p256dh','') !~ '^[A-Za-z0-9_-]{87}=?$' or coalesce(sub->'keys'->>'auth','') !~ '^[A-Za-z0-9_-]{22}(==)?$' then raise exception 'Inscrição de notificação inválida ou navegador não suportado.';end if;
  if (select count(*) from public.push_subscriptions where tenant_id=tid and user_id=auth.uid() and active and endpoint<>ep)>=10 then raise exception 'Limite de 10 dispositivos por usuário e empresa.';end if;
  -- A shared device transfers ownership only with the same browser-generated keys.
  update public.push_subscriptions set active=false,updated_at=now() where endpoint=ep and auth_key=sub->'keys'->>'auth' and user_id<>auth.uid();
  insert into public.push_subscriptions(tenant_id,user_id,endpoint,p256dh,auth_key) values(tid,auth.uid(),ep,sub->'keys'->>'p256dh',sub->'keys'->>'auth')
  on conflict(tenant_id,user_id,endpoint) do update set p256dh=excluded.p256dh,auth_key=excluded.auth_key,active=true,updated_at=now() returning id into sid;
 elsif op='unregister' then
  update public.push_subscriptions set active=false,updated_at=now() where tenant_id=tid and user_id=auth.uid() and endpoint=ep;
 elsif op='test' then
  select id into sid from public.push_subscriptions where tenant_id=tid and user_id=auth.uid() and endpoint=ep and active;
  if sid is null then raise exception 'Ative as notificações neste dispositivo primeiro.';end if;
  if exists(select 1 from app_private.push_deliveries where subscription_id=sid and event='test' and created_at>now()-interval '1 minute') then raise exception 'Aguarde um minuto para repetir o teste.';end if;
  insert into app_private.push_deliveries(subscription_id,event) values(sid,'test');perform app_private.kick_push();
 else raise exception 'Operação de notificação inválida.';end if;
 return '{"ok":true}';
end $$;

create function app_private.push_worker(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Acesso exclusivo do serviço de envio.';end if;
 if op='config' then return (select jsonb_object_agg(key,value) from app_private.secrets where key in ('push_vapid_public','push_vapid_private','push_dispatch','push_origin'));end if;
 if op='claim' then
  update app_private.push_deliveries d set state='skipped',finished_at=now() from public.push_subscriptions s where d.subscription_id=s.id and d.state='pending' and (not s.active or not app_private.push_recipient(s.tenant_id,s.user_id) or (d.appointment_id is not null and not exists(select 1 from public.appointments a where a.id=d.appointment_id and a.tenant_id=s.tenant_id and a.status in ('Agendado','Confirmado','Concluído') and app_private.push_recipient(s.tenant_id,s.user_id,a.professional_id))));
  with ready as (select id from app_private.push_deliveries where state='pending' and available_at<=now() and attempts<6 and created_at>now()-interval '1 day' order by created_at for update skip locked limit 50), leased as (
   update app_private.push_deliveries d set available_at=now()+interval '2 minutes',attempts=attempts+1,lease_token=gen_random_uuid() from ready where d.id=ready.id returning d.*)
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'lease',d.lease_token,'event',d.event,'subscription',jsonb_build_object('endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key)),
   'appointment',case when a.id is not null then jsonb_build_object('id',a.id,'starts_at',a.starts_at,'customer',c.name,'service',sv.name) else null end,'tenant',jsonb_build_object('name',t.name,'slug',t.slug))), '[]') into result
  from leased d join public.push_subscriptions s on s.id=d.subscription_id join public.tenants t on t.id=s.tenant_id
  left join public.appointments a on a.id=d.appointment_id and a.tenant_id=s.tenant_id left join public.customers c on c.id=a.customer_id and c.tenant_id=s.tenant_id left join public.services sv on sv.id=a.service_id and sv.tenant_id=s.tenant_id;
  return result;
 elsif op='finish' then
  if p->>'state' not in ('sent','retry','gone','failed') then raise exception 'Resultado inválido.';end if;
  if p->>'state'='gone' then update public.push_subscriptions s set active=false,updated_at=now() from app_private.push_deliveries d where d.id=(p->>'id')::uuid and d.lease_token=(p->>'lease')::uuid and d.state='pending' and s.id=d.subscription_id;end if;
  update app_private.push_deliveries set state=case when p->>'state'='sent' then 'sent' when p->>'state'='retry' and attempts<6 then 'pending' else 'failed' end,
   available_at=now()+make_interval(secs=>least(1800,30*(2^attempts)::int)),finished_at=case when p->>'state'='retry' and attempts<6 then null else now() end,last_status=(p->>'status')::int,lease_token=null
  where id=(p->>'id')::uuid and lease_token=(p->>'lease')::uuid and state='pending';
  return '{"ok":true}';
 else raise exception 'Operação inválida.';end if;
end $$;
revoke all on function app_private.push_recipient(uuid,uuid,uuid),app_private.kick_push(),app_private.enqueue_booking_push(),app_private.push_client(text,jsonb),app_private.push_worker(text,jsonb) from public,anon,authenticated;
grant execute on function app_private.push_client(text,jsonb) to authenticated;
grant execute on function app_private.push_worker(text,jsonb) to service_role;
create function public.agenda_push_client(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.push_client(op,p)$$;
create function public.agenda_push_worker(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.push_worker(op,p)$$;
revoke all on function public.agenda_push_client(text,jsonb),public.agenda_push_worker(text,jsonb) from public,anon,authenticated;
grant execute on function public.agenda_push_client(text,jsonb) to authenticated;
grant execute on function public.agenda_push_worker(text,jsonb) to service_role;
grant usage on schema app_private to service_role;
select cron.schedule('agenda-push-delivery','* * * * *','select app_private.kick_push()');
