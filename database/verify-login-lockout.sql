begin;
do $$
declare secret text;mail text:=gen_random_uuid()::text||'@example.invalid';uid uuid:=gen_random_uuid();admin_uid uuid;tid uuid:=gen_random_uuid();r jsonb;f jsonb;i int;denied boolean;
begin
 select value into secret from app_private.secrets where key='gateway';select user_id into admin_uid from public.platform_admins limit 1;
 insert into auth.users(id,email,email_confirmed_at) values(uid,mail,now());insert into public.platform_admins values(uid);
 insert into public.tenants(id,name,slug,responsible,email) values(tid,'Lockout fixture','lock-'||substr(uid::text,1,8),'Fixture',mail);
 insert into public.licenses(tenant_id,starts_on,expires_on) values(tid,current_date-1,current_date+30);
 insert into public.memberships(tenant_id,email,user_id,role) values(tid,mail,uid,'admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated')::text,true);
 if not app_private.master() or app_private.role(tid)<>'admin' then raise exception 'Fixture missing authorization';end if;
 for i in 1..5 loop
  r:=public.agenda_login_attempt('begin',jsonb_build_object('secret',secret,'email',upper(mail)));
  if (r->>'locked')::boolean or r->>'ticket' is null then raise exception 'Blocked before fifth invalid attempt';end if;
  f:=public.agenda_login_attempt('begin',jsonb_build_object('secret',secret,'email',mail));if f->>'busy'<>'true' then raise exception 'Parallel attempt accepted';end if;
  f:=public.agenda_login_attempt('finish',jsonb_build_object('secret',secret,'email',mail,'ticket',r->>'ticket','outcome','invalid'));
  if (f->>'remaining')::int<>5-i or (f->>'locked')::boolean<>(i=5) then raise exception 'Wrong threshold';end if;
 end loop;
 r:=public.agenda_login_attempt('begin',jsonb_build_object('secret',secret,'email',mail));if r->>'locked'<>'true' or r ? 'ticket' then raise exception 'Blocked account accepted another attempt';end if;
 if app_private.master() or app_private.role(tid) is not null then raise exception 'Blocked account retained private authorization';end if;
 denied:=false;begin perform public.agenda_api('session','{}');exception when others then denied:=true;end;if not denied then raise exception 'Blocked account session accepted';end if;
 denied:=false;begin perform public.agenda_login_admin('unlock',jsonb_build_object('email',mail,'confirmation','DESBLOQUEAR'));exception when others then denied:=true;end;if not denied then raise exception 'Blocked Master self-unlocked';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_uid,'role','authenticated')::text,true);
 perform public.agenda_login_admin('unlock',jsonb_build_object('email',mail,'confirmation','DESBLOQUEAR'));
 if app_private.login_blocked(uid) then raise exception 'Unlock failed';end if;
 r:=public.agenda_login_attempt('begin',jsonb_build_object('secret',secret,'email',mail));f:=public.agenda_login_attempt('finish',jsonb_build_object('secret',secret,'email',mail,'ticket',r->>'ticket','outcome','invalid'));
 r:=public.agenda_login_attempt('begin',jsonb_build_object('secret',secret,'email',mail));f:=public.agenda_login_attempt('finish',jsonb_build_object('secret',secret,'email',mail,'ticket',r->>'ticket','outcome','unavailable'));if f->>'remaining'<>'4' then raise exception 'Network error counted as invalid';end if;
 r:=public.agenda_login_attempt('begin',jsonb_build_object('secret',secret,'email',mail));f:=public.agenda_login_attempt('finish',jsonb_build_object('secret',secret,'email',mail,'ticket',r->>'ticket','outcome','success'));if f->>'remaining'<>'5' then raise exception 'Success did not reset failures';end if;
 denied:=false;begin perform public.agenda_login_attempt('begin',jsonb_build_object('secret','wrong-fixture-secret','email',mail));exception when others then denied:=true;end;if not denied then raise exception 'Secret guard bypassed';end if;
end $$;
rollback;
