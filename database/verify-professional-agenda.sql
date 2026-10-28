begin;
do $$
declare admin_uid uuid:=gen_random_uuid();pro_uid uuid:=gen_random_uuid();other_uid uuid:=gen_random_uuid();fresh_uid uuid:=gen_random_uuid();ta uuid:=gen_random_uuid();tb uuid:=gen_random_uuid();pa uuid:=gen_random_uuid();pb uuid:=gen_random_uuid();pc uuid:=gen_random_uuid();svc uuid:=gen_random_uuid();ca uuid:=gen_random_uuid();cb uuid:=gen_random_uuid();aa uuid:=gen_random_uuid();ab uuid:=gen_random_uuid();d jsonb;result jsonb;op text;denied boolean;mail text:=gen_random_uuid()::text||'@example.invalid';
begin
 perform set_config('agenda.restoring','on',true);
 insert into auth.users(id,email,email_confirmed_at,role) values(admin_uid,admin_uid::text||'@example.invalid',now(),'authenticated'),(pro_uid,pro_uid::text||'@example.invalid',now(),'authenticated'),(other_uid,other_uid::text||'@example.invalid',now(),'authenticated');
 insert into public.tenants(id,name,slug,responsible,email) values(ta,'Agenda fixture A','pro-'||substr(ta::text,1,8),'Fixture','fixture@example.invalid'),(tb,'Agenda fixture B','pro-'||substr(tb::text,1,8),'Fixture','fixture@example.invalid');
 insert into public.licenses(tenant_id,starts_on,expires_on) values(ta,current_date-2,current_date+60),(tb,current_date-2,current_date+60);
 insert into public.settings(tenant_id) values(ta),(tb);
 insert into public.services(id,tenant_id,name,duration,price) values(svc,ta,'Corte ✂️',30,50);
 insert into public.professionals(id,tenant_id,name,service_ids) values(pa,ta,'Profissional A',array[svc]),(pb,ta,'Profissional B',array[svc]),(pc,ta,'Novo funcionário',array[svc]);
 insert into public.memberships(tenant_id,email,user_id,role,professional_id) values(ta,admin_uid::text||'@example.invalid',admin_uid,'admin',null),(ta,pro_uid::text||'@example.invalid',pro_uid,'professional',pa),(ta,other_uid::text||'@example.invalid',other_uid,'professional',pb);
 insert into public.customers(id,tenant_id,name,phone,notes) values(ca,ta,'Cliente visível','24999999991','Segredo interno'),(cb,ta,'Cliente de outro profissional','24999999992','Outro segredo');
 insert into public.appointments(id,tenant_id,professional_id,service_id,customer_id,starts_at,ends_at,price) values(aa,ta,pa,svc,ca,'2020-02-01T10:00:00-03:00','2020-02-01T10:30:00-03:00',50),(ab,ta,pb,svc,cb,'2020-02-01T10:00:00-03:00','2020-02-01T10:30:00-03:00',50);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pro_uid,'role','authenticated')::text,true);
 d:=jsonb_build_object('tenant_id',ta,'professional_id',pb,'from','2020-02-01','to','2020-02-01');
 result:=public.agenda_professional_schedule(d);
 if jsonb_array_length(result->'appointments')<>1 or result#>>'{appointments,0,id}'<>aa::text or result#>>'{professional,id}'<>pa::text then raise exception 'Professional filter failed';end if;
 if result::text like '%Segredo%' or result::text like '%24999999992%' or result::text like '%Cliente de outro%' or result::text like '%payment_method%' or result::text like '%price%' then raise exception 'Private data leaked';end if;
 denied:=false;begin perform public.agenda_professional_schedule(d||jsonb_build_object('tenant_id',tb));exception when others then denied:=true;end;if not denied then raise exception 'Cross-company schedule accepted';end if;
 denied:=false;begin perform public.agenda_professional_schedule(d||jsonb_build_object('from','2020-01-01','to','2021-01-01'));exception when others then denied:=true;end;if not denied then raise exception 'Oversized range accepted';end if;
 foreach op in array array['workspace','status','customer','professional','settings','member','master_data','plan'] loop
  denied:=false;begin perform public.agenda_api(op,jsonb_build_object('tenant_id',ta,'id',aa,'status','Cancelado'));exception when others then denied:=true;end;if not denied then raise exception 'Legacy operation allowed: %',op;end if;
 end loop;
 foreach op in array array['appointment','status','payment'] loop
  denied:=false;begin perform public.agenda_appointment_save(op,jsonb_build_object('tenant_id',ta,'id',aa,'status','Cancelado','payment_method','Pix'));exception when others then denied:=true;end;if not denied then raise exception 'Write operation allowed: %',op;end if;
 end loop;
 denied:=false;begin perform public.agenda_finance('get',jsonb_build_object('tenant_id',ta));exception when others then denied:=true;end;if not denied then raise exception 'Finance leaked';end if;
 denied:=false;begin perform public.agenda_message_templates('get',jsonb_build_object('tenant_id',ta));exception when others then denied:=true;end;if not denied then raise exception 'WhatsApp templates leaked';end if;
 denied:=false;begin perform public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',mail));exception when others then denied:=true;end;if not denied then raise exception 'Professional created access';end if;
 update public.professionals set active=false where id=pa;
 denied:=false;begin perform public.agenda_professional_schedule(d);exception when others then denied:=true;end;if not denied then raise exception 'Inactive professional allowed';end if;
 update public.professionals set active=true where id=pa;
 update public.memberships set active=false where user_id=pro_uid;
 denied:=false;begin perform public.agenda_professional_schedule(d);exception when others then denied:=true;end;if not denied then raise exception 'Inactive membership allowed';end if;
 update public.memberships set active=true where user_id=pro_uid;
 -- Admin still has the complete workspace and can provision only its own employee.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_uid,'role','authenticated')::text,true);
 result:=public.agenda_api('workspace',jsonb_build_object('tenant_id',ta));if jsonb_array_length(result->'appointments')<>2 then raise exception 'Admin workspace regression';end if;
 denied:=false;begin perform public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',tb,'professional_id',pc,'email',mail));exception when others then denied:=true;end;if not denied then raise exception 'Cross-company access creation allowed';end if;
 denied:=false;begin perform public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',admin_uid::text||'@example.invalid'));exception when others then denied:=true;end;if not denied then raise exception 'Admin account reused';end if;
 result:=public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',mail));if result->>'user_id' is not null then raise exception 'Unexpected account';end if;
 insert into auth.users(id,email,email_confirmed_at,role,raw_app_meta_data) values(fresh_uid,mail,now(),'authenticated',jsonb_build_object('agenda_professional_actor',admin_uid,'agenda_professional_id',pc,'agenda_professional_tenant',ta));
 result:=public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',mail));if result->>'user_id'<>fresh_uid::text then raise exception 'Interrupted provision not resumed';end if;
 perform public.agenda_professional_access('finish',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',mail,'account_id',fresh_uid));
 result:=public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',mail));if result->>'complete'<>'true' then raise exception 'Retry not idempotent';end if;
 if not exists(select 1 from public.memberships where user_id=fresh_uid and tenant_id=ta and professional_id=pc and role='professional') then raise exception 'Wrong permission granted';end if;
 denied:=false;begin perform public.agenda_professional_access('prepare',jsonb_build_object('tenant_id',ta,'professional_id',pc,'email',mail,'password','forbidden'));exception when others then denied:=true;end;if not denied then raise exception 'Password reached business RPC';end if;
 if (select status from public.appointments where id=aa)<>'Agendado' or (select payment_method from public.appointments where id=aa)<>'A combinar' then raise exception 'Read-only appointment was modified';end if;
end $$;
rollback;
