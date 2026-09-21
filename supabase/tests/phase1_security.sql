-- Execute depois da migracao da Fase 1.
-- O script falha imediatamente se alguma garantia critica regredir.

begin;

do $phase1_test$
declare
  v_missing_rls integer;
  v_policy_count integer;
begin
  select count(*)
  into v_missing_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in (
      'usuarios', 'pacientes', 'procedimentos', 'agendamentos', 'anamneses'
    )
    and not c.relrowsecurity;

  if v_missing_rls <> 0 then
    raise exception 'Falha: % tabelas publicas estao sem RLS.', v_missing_rls;
  end if;

  if has_table_privilege('anon', 'public.usuarios', 'select')
     or has_table_privilege('anon', 'public.pacientes', 'select')
     or has_table_privilege('anon', 'public.agendamentos', 'select')
     or has_table_privilege('anon', 'public.anamneses', 'select') then
    raise exception 'Falha: anon recebeu leitura de dados privados.';
  end if;

  if not has_table_privilege('anon', 'public.procedimentos', 'select') then
    raise exception 'Falha: o catalogo publico nao pode ser consultado.';
  end if;

  if has_table_privilege('authenticated', 'public.usuarios', 'delete')
     or has_table_privilege('authenticated', 'public.pacientes', 'delete')
     or has_table_privilege('authenticated', 'public.procedimentos', 'delete') then
    raise exception 'Falha: privilegio destrutivo excessivo.';
  end if;

  if has_function_privilege(
       'anon',
       'public.claim_legacy_profile(text,text)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.create_access_invite(uuid)',
       'execute'
     )
     or has_function_privilege(
       'anon',
       'public.criar_agendamento_interno(uuid,date,text,uuid,text,text)',
       'execute'
     ) then
    raise exception 'Falha: uma RPC interna esta exposta ao anon.';
  end if;

  if not has_function_privilege(
       'anon',
       'public.get_horarios_ocupados(date)',
       'execute'
     )
     or not has_function_privilege(
       'anon',
       'public.criar_agendamento_publico(uuid,date,text,text,text)',
       'execute'
     ) then
    raise exception 'Falha: uma RPC publica esta indisponivel.';
  end if;

  if has_schema_privilege('authenticated', 'private', 'usage')
     or has_schema_privilege('anon', 'private', 'usage') then
    raise exception 'Falha: o schema private esta exposto.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'private.has_permission(text)',
       'execute'
     ) then
    raise exception 'Falha: helper de autorizacao indisponivel.';
  end if;

  select count(*)
  into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename in (
      'usuarios', 'pacientes', 'procedimentos', 'agendamentos', 'anamneses'
    );

  if v_policy_count < 15 then
    raise exception 'Falha: somente % policies foram encontradas.', v_policy_count;
  end if;

  if exists (select 1 from public.usuarios where senha is not null) then
    raise exception 'Falha: existe senha legada em texto simples.';
  end if;

  if to_regclass('public.agendamentos_data_hora_key') is null then
    raise exception 'Falha: indice unico de horario ausente.';
  end if;
end
$phase1_test$;

select 'phase1_security_ok' as status;

rollback;
