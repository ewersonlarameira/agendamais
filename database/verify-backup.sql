begin;
create temporary table restored_financial_entries(like public.financial_entries including all) on commit drop;
do $$
declare uid uuid:=gen_random_uuid();tid uuid;eid uuid;backup jsonb;denied boolean:=false;
begin
 insert into auth.users(id,email,email_confirmed_at) values(uid,'backup-fixture@example.invalid',now());
 perform set_config('request.jwt.claim.sub',uid::text,true);
 begin perform public.agenda_backup_export();exception when others then denied:=true;end;if not denied then raise exception 'FAIL ordinary account can export platform';end if;
 insert into public.platform_admins values(uid);
 insert into public.tenants(name,slug,responsible,email) values('Backup fixture','backup-fixture-'||substr(uid::text,1,8),'Fixture','backup-fixture@example.invalid') returning id into tid;
 insert into public.financial_entries(tenant_id,kind,description,category,amount,due_on,settled_on,payment_method,notes) values(tid,'income','Receita fixture','Teste',35.57,current_date,current_date,'Pix','Observação de teste com emoji ✂️') returning id into eid;
 insert into public.financial_entries(tenant_id,kind,description,category,amount,due_on,voided_at) values(tid,'expense','Despesa anulada fixture','Teste',12.23,current_date,now());
 backup:=public.agenda_backup_export();
 if backup->>'format'<>'agenda-business-snapshot' or (backup->>'version')::int<>2 then raise exception 'FAIL snapshot format';end if;
 if not backup->'tables' ?& array['financial_entries','audit_logs','whatsapp_templates','tenants','licenses','appointments','settings','memberships','plans'] then raise exception 'FAIL incomplete business tables';end if;
 if backup->'tables' ?| array['secrets','users','sessions','push_subscriptions','push_deliveries'] then raise exception 'FAIL private credentials exported';end if;
 insert into pg_temp.restored_financial_entries select * from jsonb_populate_recordset(null::public.financial_entries,backup->'tables'->'financial_entries');
 if not exists(select 1 from pg_temp.restored_financial_entries where id=eid and amount=35.57 and payment_method='Pix' and notes like '%✂️%') then raise exception 'FAIL JSON round-trip lost financial data';end if;
 if (select sum(case when kind='income' then amount else -amount end) from pg_temp.restored_financial_entries where tenant_id=tid and voided_at is null)<>35.57 then raise exception 'FAIL restored financial totals';end if;
 if (select count(*) from pg_temp.restored_financial_entries where tenant_id=tid and voided_at is not null)<>1 then raise exception 'FAIL voided history omitted';end if;
 if exists(select 1 from public.financial_entries original join pg_temp.restored_financial_entries restored using(id) where original.tenant_id=tid and to_jsonb(original) is distinct from to_jsonb(restored)) then raise exception 'FAIL restored records differ';end if;
 perform set_config('request.jwt.claim.sub','',true);denied:=false;begin perform public.agenda_backup_export();exception when others then denied:=true;end;if not denied then raise exception 'FAIL anonymous export';end if;
end $$;
select 'PASS: Master-only snapshot, business table coverage, credential exclusion and financial JSON restore into temporary tables (not a full disaster recovery test)' as result;
rollback;
