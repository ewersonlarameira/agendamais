begin;
do $$
declare visible uuid:=gen_random_uuid();inactive uuid:=gen_random_uuid();deleted uuid:=gen_random_uuid();catalog jsonb;plan jsonb;fields text[];
begin
 insert into public.plans(id,name,amount,months,description,active) values(visible,'Plano de teste 🧪',89.90,1,E'✅ Recurso de teste\n📅 Agenda',true),(inactive,'Inativo fixture',1,1,'Não publicar',false),(deleted,'Excluído fixture',1,1,'Não publicar',true);
 update public.plans set deleted_at=now() where id=deleted;
 catalog:=public.agenda_public_plans();
 select value into plan from jsonb_array_elements(catalog) where value->>'id'=visible::text;
 if plan is null or plan->>'name'<>'Plano de teste 🧪' or plan->>'description'<>E'✅ Recurso de teste\n📅 Agenda' then raise exception 'Plan contents or Unicode lost';end if;
 select array_agg(k order by k) into fields from jsonb_object_keys(plan) k;
 if fields<>array['amount','description','id','months','name']::text[] then raise exception 'Unexpected public fields';end if;
 if exists(select 1 from jsonb_array_elements(catalog) r where r->>'id' in (inactive::text,deleted::text)) then raise exception 'Hidden plan published';end if;
 update public.plans set name='Plano atualizado',amount=999.90,months=12,description=E'👑 Alterado no Master\n✅ Outro benefício' where id=visible;
 catalog:=public.agenda_public_plans();select value into plan from jsonb_array_elements(catalog) where value->>'id'=visible::text;
 if plan->>'name'<>'Plano atualizado' or (plan->>'amount')::numeric<>999.90 or plan->>'months'<>'12' or plan->>'description'<>E'👑 Alterado no Master\n✅ Outro benefício' then raise exception 'Updated plan not reflected';end if;
 if has_table_privilege('anon','public.plans','SELECT') or not has_function_privilege('anon','public.agenda_public_plans()','EXECUTE') then raise exception 'Public access privilege mismatch';end if;
end $$;
rollback;
