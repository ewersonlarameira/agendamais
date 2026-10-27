begin;
do $$
declare uid uuid:=gen_random_uuid();ordinary uuid:=gen_random_uuid();pid uuid;tid uuid;result jsonb;denied boolean;
begin
 insert into auth.users(id,email,email_confirmed_at) values(uid,'plan-master-fixture@example.invalid',now()),(ordinary,'plan-user-fixture@example.invalid',now());
 insert into public.platform_admins values(uid);
 perform set_config('request.jwt.claim.sub',uid::text,true);
 result:=public.agenda_plan_save(jsonb_build_object('name','Plano fixture','months',1,'amount',49.90,'description',E'📅 Agenda\n📲 WhatsApp'));
 pid:=(result->>'id')::uuid;
 if not exists(select 1 from public.plans where id=pid and months=1 and amount=49.90 and description=E'📅 Agenda\n📲 WhatsApp') then raise exception 'FAIL monthly save';end if;
 if not exists(select 1 from jsonb_array_elements(app_private.gateway('master_data','{}')->'plans') p where p->>'id'=pid::text and p->>'description'=E'📅 Agenda\n📲 WhatsApp') then raise exception 'FAIL description missing on reload';end if;
 insert into public.tenants(name,slug,responsible,email) values('Plan fixture','plan-fixture-'||substr(uid::text,1,8),'Fixture','plan-fixture@example.invalid') returning id into tid;
 insert into public.licenses(tenant_id,plan_id,starts_on,expires_on,amount) values(tid,pid,current_date,current_date+30,49.90);
 perform public.agenda_plan_save(jsonb_build_object('id',pid,'name','Plano fixture anual','months',12,'amount',499.90,'description','✅ Plano anual'));
 if not exists(select 1 from public.plans where id=pid and months=12 and amount=499.90 and description='✅ Plano anual') then raise exception 'FAIL annual edit';end if;
 if not exists(select 1 from public.licenses where tenant_id=tid and expires_on=current_date+30 and amount=49.90) then raise exception 'FAIL existing license changed';end if;
 denied:=false;begin perform public.agenda_plan_save(jsonb_build_object('name','Invalid period','months',3,'amount',1));exception when others then denied:=true;end;if not denied then raise exception 'FAIL new custom period accepted';end if;
 denied:=false;begin perform public.agenda_plan_save(jsonb_build_object('name','Too long','months',1,'amount',1,'description',repeat('a',4001)));exception when others then denied:=true;end;if not denied then raise exception 'FAIL oversized description accepted';end if;
 denied:=false;begin perform public.agenda_plan_save(jsonb_build_object('name','Invalid price','months',1,'amount',-1));exception when others then denied:=true;end;if not denied then raise exception 'FAIL invalid amount accepted';end if;
 -- Compatibility: descriptions can be added to pre-existing non-monthly/yearly plans.
 update public.plans set months=3 where id=pid;
 perform public.agenda_plan_save(jsonb_build_object('id',pid,'name','Legado fixture','months',3,'amount',1,'description','Preservado'));
 if not exists(select 1 from public.plans where id=pid and months=3 and description='Preservado') then raise exception 'FAIL legacy period changed';end if;
 perform set_config('request.jwt.claim.sub',ordinary::text,true);
 denied:=false;begin perform public.agenda_plan_save(jsonb_build_object('id',pid,'name','Forbidden','months',1,'amount',1));exception when others then denied:=true;end;if not denied then raise exception 'FAIL ordinary user can change plans';end if;
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;begin perform public.agenda_plan_save(jsonb_build_object('name','Forbidden','months',1,'amount',1));exception when others then denied:=true;end;if not denied then raise exception 'FAIL anonymous can create plans';end if;
 if has_function_privilege('anon','public.agenda_plan_save(jsonb)','execute') then raise exception 'FAIL anonymous execute granted';end if;
end $$;
select 'PASS: monthly/yearly plan persistence, multiline descriptions, reload, legacy compatibility, license preservation and authorization' as result;
rollback;
