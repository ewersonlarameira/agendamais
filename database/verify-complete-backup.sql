begin;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
declare actor uuid; d jsonb; c jsonb; t uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); customer uuid:=gen_random_uuid(); a uuid; i int:=0; status text; before_customers bigint; before_appointments bigint;
begin
 select user_id into actor from public.platform_admins limit 1;
 select count(*) into before_customers from public.customers;
 select count(*) into before_appointments from public.appointments;
 d:=app_private.recovery_snapshot(actor);
 -- Synthetic records exist only inside this transaction, which always rolls back.
 d:=jsonb_set(d,'{accounts}',d->'accounts'||jsonb_build_array(jsonb_build_object('id',u,'instance_id','00000000-0000-0000-0000-000000000000','aud','authenticated','role','authenticated','email',u::text||'@example.invalid','encrypted_password',crypt('fixture-only-password',gen_salt('bf')),'email_confirmed_at',now(),'raw_app_meta_data',jsonb_build_object('provider','email','providers',array['email']),'raw_user_meta_data','{}'::jsonb,'created_at',now(),'updated_at',now(),'is_sso_user',false,'is_anonymous',false)));
 d:=jsonb_set(d,'{identities}',d->'identities'||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'provider_id',u,'user_id',u,'provider','email','identity_data',jsonb_build_object('sub',u,'email',u::text||'@example.invalid'),'created_at',now(),'updated_at',now())));
 d:=jsonb_set(d,'{tables,tenants}',d#>'{tables,tenants}'||jsonb_build_array(jsonb_build_object('id',t,'name','Recovery fixture','slug','recovery-'||substr(t::text,1,8),'responsible','Fixture','email','fixture@example.invalid','phone','','status','active','created_at',now())));
 d:=jsonb_set(d,'{tables,services}',d#>'{tables,services}'||jsonb_build_array(jsonb_build_object('id',s,'tenant_id',t,'name','Corte ✂️','duration',30,'price',45.50,'emoji','✂️','active',true)));
 d:=jsonb_set(d,'{tables,professionals}',d#>'{tables,professionals}'||jsonb_build_array(jsonb_build_object('id',p,'tenant_id',t,'name','Fixture','phone','','photo','','active',true,'schedule','{}'::jsonb,'service_ids',array[s])));
 d:=jsonb_set(d,'{tables,customers}',d#>'{tables,customers}'||jsonb_build_array(jsonb_build_object('id',customer,'tenant_id',t,'name','Cliente 🧑🏽‍💼','phone','24999999999','birthday','1990-01-01','notes','Histórico íntegro','created_at',now())));
 d:=jsonb_set(d,'{tables,memberships}',d#>'{tables,memberships}'||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'tenant_id',t,'email',u::text||'@example.invalid','user_id',u,'role','admin','professional_id',null,'active',true)));
 foreach status in array array['Agendado','Confirmado','Concluído','Cancelado','Não compareceu','Bloqueado'] loop
  a:=gen_random_uuid(); i:=i+1;
  d:=jsonb_set(d,'{tables,appointments}',d#>'{tables,appointments}'||jsonb_build_array(jsonb_build_object('id',a,'tenant_id',t,'professional_id',p,'service_id',s,'customer_id',customer,'starts_at','2020-01-01 10:00Z'::timestamptz+i*interval '1 day','ends_at','2020-01-01 10:30Z'::timestamptz+i*interval '1 day','price',45.50,'status',status,'protocol',a::text,'notes','Histórico','created_at',now(),'payment_method','A combinar')));
 end loop;
 c:=app_private.recovery_merge(actor,d,false);
 if (c->'customers'->>'missing')::int<>1 or (c->'appointments'->>'missing')::int<>6 or exists(select 1 from public.tenants where id=t) then raise exception 'Preview did not roll back';end if;
 c:=app_private.recovery_merge(actor,d,true);
 if (select count(*) from public.customers)<>before_customers+1 or (select count(*) from public.appointments)<>before_appointments+6 then raise exception 'Row count mismatch';end if;
 if (select count(distinct x.status) from public.appointments x where tenant_id=t)<>6 then raise exception 'History statuses lost';end if;
 if not exists(select 1 from auth.users where id=u and crypt('fixture-only-password',encrypted_password)=encrypted_password) then raise exception 'Password hash not recovered';end if;
 if exists(select 1 from app_private.push_deliveries x join public.appointments a on a.id=x.appointment_id where a.tenant_id=t) then raise exception 'Restore queued notifications';end if;
 update public.customers set name='Alterado depois da cópia' where id=customer;
 c:=app_private.recovery_merge(actor,d,true);
 if (c->'customers'->>'inserted')::int<>0 or (select name from public.customers where id=customer)<>'Alterado depois da cópia' then raise exception 'Existing record overwritten';end if;
 -- Deliberately invalid cross-company relation must roll the entire merge back.
 d:=jsonb_set(d,'{tables,customers,0,tenant_id}',to_jsonb(gen_random_uuid()));
 begin perform app_private.recovery_merge(actor,d,true);raise exception 'Conflict accepted' using errcode='ZB002';exception when sqlstate 'ZB002' then raise;when others then null;end;
end $$;
rollback;
