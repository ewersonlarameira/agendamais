-- Additive plan metadata; existing licenses and legacy plan periods are preserved.
alter table public.plans add column description text not null default '' check(char_length(description)<=4000);

create function app_private.plan_save(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 pid uuid:=nullif(p->>'id','')::uuid;
 label text:=btrim(p->>'name');
 details text:=btrim(coalesce(p->>'description',''));
 period int:=(p->>'months')::int;
 price numeric:=(p->>'amount')::numeric;
 previous_period int;
begin
 if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
 if label is null or char_length(label) not between 1 and 120 then raise exception 'Informe um nome de plano com até 120 caracteres.';end if;
 if char_length(details)>4000 then raise exception 'A descrição deve ter até 4.000 caracteres.';end if;
 if price is null or price<0 or price>99999999.99 or price::text in ('NaN','Infinity','-Infinity') or price<>round(price,2) then raise exception 'Informe um valor válido com até duas casas decimais.';end if;
 if pid is not null then
  select months into previous_period from public.plans where id=pid and deleted_at is null for update;
  if not found then raise exception 'Plano não encontrado ou excluído.';end if;
 end if;
 -- A pre-existing custom period can be retained, but new plans use monthly/yearly.
 if period is null or (period not in (1,12) and period is distinct from previous_period) then raise exception 'Selecione renovação mensal ou anual.';end if;
 if pid is null then
  insert into public.plans(name,amount,months,description) values(label,price,period,details) returning id into pid;
 else
  update public.plans set name=label,amount=price,months=period,description=details where id=pid;
 end if;
 insert into public.audit_logs(actor,action) values(auth.uid(),'Plano salvo: '||label);
 return jsonb_build_object('ok',true,'id',pid);
end $$;
revoke all on function app_private.plan_save(jsonb) from public,anon,authenticated;
grant execute on function app_private.plan_save(jsonb) to authenticated;
create function public.agenda_plan_save(p jsonb) returns jsonb
language sql security invoker set search_path='' as $$select app_private.plan_save(p)$$;
revoke all on function public.agenda_plan_save(jsonb) from public,anon,authenticated;
grant execute on function public.agenda_plan_save(jsonb) to authenticated;
