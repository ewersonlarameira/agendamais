begin;
do $$
declare owner_id uuid:=gen_random_uuid();client_id uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();req uuid:=gen_random_uuid();plan_id uuid;tid uuid;p jsonb;r jsonb;denied boolean;mail text;company_slug text;
begin
 mail:='access-fixture-'||substr(client_id::text,1,8)||'@example.invalid';company_slug:='access-fixture-'||substr(client_id::text,1,8);
 insert into auth.users(id,email,email_confirmed_at) values(owner_id,'access-master-fixture@example.invalid',now()),(outsider,'access-outsider-fixture@example.invalid',now());
 insert into public.platform_admins values(owner_id);
 insert into public.plans(name,amount,months) values('Access fixture',49.90,1) returning id into plan_id;
 p:=jsonb_build_object('name','Access fixture','responsible','Fixture','email',mail,'slug',company_slug,'document_type','CPF','document_number','52998224725','plan_id',plan_id,'starts_on',current_date,'expires_on',current_date+30,'amount',49.90,'paid',false);
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 denied:=false;begin perform public.agenda_company_access('prepare',p,req);exception when others then denied:=true;end;if not denied then raise exception 'FAIL ordinary user can provision';end if;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 r:=public.agenda_company_access('prepare',p,req);
 if (r->>'complete')::boolean or r->>'user_id' is not null then raise exception 'FAIL new request state';end if;
 denied:=false;begin perform public.agenda_company_access('prepare',p||'{"initial_password":"must-not-enter-business-sql"}',req);exception when others then denied:=true;end;if not denied then raise exception 'FAIL password accepted by business RPC';end if;
 denied:=false;begin perform public.agenda_company_access('prepare',p||jsonb_build_object('slug','master'),req);exception when others then denied:=true;end;if not denied then raise exception 'FAIL reserved slug accepted';end if;
 denied:=false;begin perform public.agenda_company_access('prepare',p||jsonb_build_object('email','access-master-fixture@example.invalid'),req);exception when others then denied:=true;end;if not denied then raise exception 'FAIL existing account can be replaced';end if;
 insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values(client_id,mail,now(),jsonb_build_object('agenda_company_actor',owner_id,'agenda_company_slug',company_slug,'agenda_company_request',req));
 -- Interrupted onboarding can resume even if a new browser form generates a request ID.
 r:=public.agenda_company_access('prepare',p,gen_random_uuid());
 if r->>'user_id'<>client_id::text or r->>'request_id'<>req::text then raise exception 'FAIL pending account recovery';end if;
 r:=public.agenda_company_access('finish',p,req);tid:=(r->>'tenant_id')::uuid;
 if not exists(select 1 from public.memberships where tenant_id=tid and user_id=client_id and role='admin' and active) then raise exception 'FAIL initial admin not bound';end if;
 r:=public.agenda_company_access('finish',p,req);
 if (r->>'tenant_id')::uuid<>tid or (select count(*) from public.tenants where public.tenants.slug=company_slug)<>1 then raise exception 'FAIL retry creates duplicate';end if;
 perform set_config('request.jwt.claim.sub',client_id::text,true);
 if app_private.role(tid) is distinct from 'admin' then raise exception 'FAIL client admin access';end if;
 if (app_private.gateway('workspace',jsonb_build_object('tenant_id',tid))->'tenant'->>'id')::uuid<>tid then raise exception 'FAIL client workspace';end if;
 if app_private.master() then raise exception 'FAIL client received Master access';end if;
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 if app_private.role(tid) is not null then raise exception 'FAIL outsider has tenant role';end if;
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;begin perform public.agenda_company_access('prepare',p,req);exception when others then denied:=true;end;if not denied then raise exception 'FAIL anonymous provision';end if;
 if has_function_privilege('anon','public.agenda_company_access(text,jsonb,uuid)','execute') then raise exception 'FAIL anonymous execute';end if;
end $$;
select 'PASS: Master authorization, credential rejection, reserved links, existing account protection, resumable provisioning, idempotent creation and tenant access isolation' as result;
rollback;
