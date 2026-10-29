-- Operational authentication controls; no passwords are stored here.
create table app_private.login_guard (
 email text primary key,
 failures int not null default 0 check(failures between 0 and 5),
 blocked_at timestamptz,
 attempt_id uuid,
 attempt_until timestamptz,
 updated_at timestamptz not null default now()
);
alter table app_private.login_guard enable row level security;
revoke all on app_private.login_guard from public,anon,authenticated;
create policy login_guard_internal_only on app_private.login_guard to authenticated using(false) with check(false);

create function app_private.login_blocked(uid uuid default auth.uid()) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.login_guard g join auth.users u on lower(u.email)=g.email where u.id=uid and g.blocked_at is not null)
$$;
revoke all on function app_private.login_blocked(uuid) from public,anon,authenticated;

create function app_private.login_attempt(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare expected text;mail text;g app_private.login_guard;ticket uuid;
begin
 select value into expected from app_private.secrets where key='gateway';
 if expected is null or p->>'secret' is distinct from expected then raise exception 'Acesso negado.';end if;
 if p ?| array['password','initial_password','confirm_password'] then raise exception 'Senhas não devem entrar no banco de negócio.';end if;
 mail:=lower(btrim(p->>'email'));
 if mail is null or length(mail)>254 or mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Informe um e-mail válido.';end if;
 insert into app_private.login_guard(email) values(mail) on conflict do nothing;
 select * into g from app_private.login_guard where email=mail for update;
 if g.blocked_at is not null then return jsonb_build_object('locked',true,'remaining',0);end if;
 if op='begin' then
  if g.attempt_until>now() then return jsonb_build_object('busy',true);end if;
  ticket:=gen_random_uuid();
  update app_private.login_guard set attempt_id=ticket,attempt_until=now()+interval '90 seconds',updated_at=now() where email=mail;
  return jsonb_build_object('ticket',ticket,'remaining',5-g.failures,'locked',false);
 end if;
 if op<>'finish' or g.attempt_id is null or g.attempt_until is null or (p->>'ticket')::uuid is distinct from g.attempt_id or g.attempt_until<now() then raise exception 'Tentativa expirada. Entre novamente.';end if;
 if p->>'outcome' is null or p->>'outcome' not in ('success','invalid','unavailable') then raise exception 'Resultado inválido.';end if;
 update app_private.login_guard set failures=case when p->>'outcome'='success' then 0 when p->>'outcome'='invalid' then least(5,failures+1) else failures end,
 blocked_at=case when p->>'outcome'='invalid' and failures>=4 then now() else blocked_at end,
 attempt_id=null,attempt_until=null,updated_at=now() where email=mail returning * into g;
 return jsonb_build_object('locked',g.blocked_at is not null,'remaining',5-g.failures);
end $$;
revoke all on function app_private.login_attempt(text,jsonb) from public,anon;
grant execute on function app_private.login_attempt(text,jsonb) to anon,authenticated;
create function public.agenda_login_attempt(op text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select app_private.login_attempt(op,p)$$;
revoke all on function public.agenda_login_attempt(text,jsonb) from public;
grant execute on function public.agenda_login_attempt(text,jsonb) to anon,authenticated;

-- Existing authenticated sessions must not bypass an account lock through RPCs.
do $$declare definition text;begin
 select pg_get_functiondef('app_private.master()'::regprocedure) into definition;
 definition:=replace(definition,'where user_id=auth.uid()','where user_id=auth.uid() and not app_private.login_blocked()');execute definition;
 select pg_get_functiondef('app_private.role(uuid)'::regprocedure) into definition;
 definition:=replace(definition,'where m.tenant_id=t','where m.tenant_id=t and not app_private.login_blocked()');execute definition;
 select pg_get_functiondef('app_private.gateway(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,'if op=''session'' then',E'if app_private.login_blocked() then raise exception ''Acesso bloqueado. Entre em contato com o suporte.'';end if;\nif op=''session'' then');execute definition;
 select pg_get_functiondef('app_private.recovery_gate(uuid)'::regprocedure) into definition;
 definition:=replace(definition,'or actor is null or','or actor is null or app_private.login_blocked(actor) or');execute definition;
 select pg_get_functiondef('app_private.push_recipient(uuid,uuid,uuid)'::regprocedure) into definition;
 definition:=replace(definition,'where m.tenant_id=t','where m.tenant_id=t and not app_private.login_blocked(u)');execute definition;
end $$;

create function app_private.login_admin(op text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare mail text;n int;
begin
 if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
 if op='list' then return coalesce((select jsonb_agg(jsonb_build_object('email',email,'failures',failures,'blocked_at',blocked_at) order by blocked_at desc) from app_private.login_guard where blocked_at is not null),'[]'::jsonb);end if;
 if op<>'unlock' or p->>'confirmation' is distinct from 'DESBLOQUEAR' then raise exception 'Confirme o desbloqueio.';end if;
 mail:=lower(btrim(p->>'email'));
 update app_private.login_guard set failures=0,blocked_at=null,attempt_id=null,attempt_until=null,updated_at=now() where email=mail and blocked_at is not null;
 get diagnostics n=row_count;
 if n>0 then insert into public.audit_logs(actor,action) values(auth.uid(),'Desbloqueio de acesso pelo suporte: '||mail);end if;
 return jsonb_build_object('ok',true,'unlocked',n>0);
end $$;
revoke all on function app_private.login_admin(text,jsonb) from public,anon;
grant execute on function app_private.login_admin(text,jsonb) to authenticated;
create function public.agenda_login_admin(op text,p jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select app_private.login_admin(op,p)$$;
revoke all on function public.agenda_login_admin(text,jsonb) from public,anon;
grant execute on function public.agenda_login_admin(text,jsonb) to authenticated;
