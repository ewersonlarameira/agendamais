-- AgendaMais - Fase 1 de seguranca
-- Autenticacao Supabase, privilegios minimos, RLS e agendamento publico seguro.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Evolucao do modelo sem apagar dados existentes
-- ---------------------------------------------------------------------------

alter table public.usuarios
  add column if not exists auth_user_id uuid,
  add column if not exists email text,
  add column if not exists ativo boolean not null default true,
  add column if not exists legacy_password_hash text,
  add column if not exists legacy_claimed_at timestamptz;

alter table public.usuarios
  alter column senha drop not null;

update public.usuarios
set ativo = false
where coalesce(permissoes, '[]'::jsonb) ? 'inativo';

update public.usuarios
set permissoes = coalesce(permissoes, '[]'::jsonb) - 'inativo'
where coalesce(permissoes, '[]'::jsonb) ? 'inativo';

-- Converte imediatamente as senhas legadas em hashes bcrypt e elimina o texto
-- simples. O hash so pode ser usado uma vez para vincular o perfil ao Auth.
update public.usuarios
set legacy_password_hash = extensions.crypt(senha, extensions.gen_salt('bf', 10)),
    senha = null
where senha is not null
  and length(senha) > 0
  and legacy_password_hash is null;

alter table public.pacientes
  add column if not exists whatsapp_normalizado text;

update public.pacientes
set whatsapp_normalizado = nullif(regexp_replace(coalesce(whatsapp, ''), '[^0-9]', '', 'g'), '')
where whatsapp_normalizado is null;

alter table public.agendamentos
  add column if not exists paciente_id uuid,
  add column if not exists procedimento_id uuid,
  add column if not exists created_by uuid;

update public.agendamentos a
set paciente_id = (
  select p.id
  from public.pacientes p
  where lower(p.nome) = lower(a.paciente_nome)
  order by p.created_at, p.id
  limit 1
)
where a.paciente_id is null;

update public.agendamentos a
set procedimento_id = (
  select p.id
  from public.procedimentos p
  where lower(p.nome) = lower(a.procedimento_nome)
  order by p.created_at, p.id
  limit 1
)
where a.procedimento_id is null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'usuarios_auth_user_id_fkey'
      and conrelid = 'public.usuarios'::regclass
  ) then
    alter table public.usuarios
      add constraint usuarios_auth_user_id_fkey
      foreign key (auth_user_id) references auth.users(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamentos_paciente_id_fkey'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table public.agendamentos
      add constraint agendamentos_paciente_id_fkey
      foreign key (paciente_id) references public.pacientes(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamentos_procedimento_id_fkey'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table public.agendamentos
      add constraint agendamentos_procedimento_id_fkey
      foreign key (procedimento_id) references public.procedimentos(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamentos_created_by_fkey'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table public.agendamentos
      add constraint agendamentos_created_by_fkey
      foreign key (created_by) references auth.users(id) on delete set null;
  end if;
end
$$;

do $$
begin
  if exists (
    select 1
    from public.agendamentos
    group by data_agendamento, hora
    having count(*) > 1
  ) then
    raise exception 'Existem horarios duplicados em agendamentos. Resolva-os antes da migracao.';
  end if;
end
$$;

create unique index if not exists usuarios_auth_user_id_key
  on public.usuarios (auth_user_id)
  where auth_user_id is not null;

create unique index if not exists usuarios_nick_lower_key
  on public.usuarios (lower(nick));

create index if not exists pacientes_whatsapp_normalizado_idx
  on public.pacientes (whatsapp_normalizado)
  where whatsapp_normalizado is not null;

create unique index if not exists agendamentos_data_hora_key
  on public.agendamentos (data_agendamento, hora);

create index if not exists agendamentos_data_idx
  on public.agendamentos (data_agendamento);

create index if not exists agendamentos_agrupador_idx
  on public.agendamentos (id_agrupador);

create index if not exists agendamentos_paciente_id_idx
  on public.agendamentos (paciente_id);

create index if not exists agendamentos_procedimento_id_idx
  on public.agendamentos (procedimento_id);

create index if not exists procedimentos_status_nome_idx
  on public.procedimentos (status, nome);

create sequence if not exists public.agendamento_agrupador_seq as bigint;

select setval(
  'public.agendamento_agrupador_seq'::regclass,
  greatest(
    coalesce((select max(id_agrupador) from public.agendamentos), 0) + 1,
    1000000
  ),
  false
);

revoke all on sequence public.agendamento_agrupador_seq from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Estruturas privadas de ativacao e protecao contra abuso
-- ---------------------------------------------------------------------------

create table if not exists private.legacy_claim_attempts (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  attempts integer not null default 0,
  window_started_at timestamptz not null default now(),
  locked_until timestamptz,
  last_attempt_at timestamptz not null default now()
);

create table if not exists private.access_invites (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.usuarios(id) on delete cascade,
  code_hash text not null unique,
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists access_invites_profile_idx
  on private.access_invites (profile_id, expires_at)
  where used_at is null;

create table if not exists private.public_booking_limits (
  contact_hash text primary key,
  attempts integer not null default 0,
  window_started_at timestamptz not null default now(),
  last_attempt_at timestamptz not null default now()
);

revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helpers de autorizacao. O schema private nao e exposto pela Data API.
-- ---------------------------------------------------------------------------

create or replace function private.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios u
    where u.auth_user_id = (select auth.uid())
      and u.ativo
      and not (coalesce(u.permissoes, '[]'::jsonb) ? 'inativo')
  );
$$;

create or replace function private.has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuarios u
    where u.auth_user_id = (select auth.uid())
      and u.ativo
      and not (coalesce(u.permissoes, '[]'::jsonb) ? 'inativo')
      and coalesce(u.permissoes, '[]'::jsonb) ? p_permission
  );
$$;

revoke all on function private.is_active_staff() from public, anon;
revoke all on function private.has_permission(text) from public, anon;
grant execute on function private.is_active_staff() to authenticated;
grant execute on function private.has_permission(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Funcoes publicas controladas
-- ---------------------------------------------------------------------------

create or replace function public.claim_legacy_profile(
  p_nick text,
  p_legacy_password text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_profile_id uuid;
  v_email text;
  v_locked_until timestamptz;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Autenticacao obrigatoria.');
  end if;

  if exists (select 1 from public.usuarios where auth_user_id = v_uid) then
    return jsonb_build_object('ok', true, 'message', 'Acesso ja vinculado.');
  end if;

  select locked_until
  into v_locked_until
  from private.legacy_claim_attempts
  where auth_user_id = v_uid;

  if v_locked_until is not null and v_locked_until > now() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Muitas tentativas. Aguarde 15 minutos.'
    );
  end if;

  select u.id
  into v_profile_id
  from public.usuarios u
  where lower(u.nick) = lower(trim(p_nick))
    and u.ativo
    and u.auth_user_id is null
    and u.legacy_password_hash is not null
    and u.legacy_password_hash = extensions.crypt(p_legacy_password, u.legacy_password_hash)
  for update;

  if v_profile_id is null then
    insert into private.legacy_claim_attempts (
      auth_user_id, attempts, window_started_at, locked_until, last_attempt_at
    )
    values (v_uid, 1, now(), null, now())
    on conflict (auth_user_id) do update
    set attempts = case
          when private.legacy_claim_attempts.window_started_at < now() - interval '15 minutes'
            then 1
          else private.legacy_claim_attempts.attempts + 1
        end,
        window_started_at = case
          when private.legacy_claim_attempts.window_started_at < now() - interval '15 minutes'
            then now()
          else private.legacy_claim_attempts.window_started_at
        end,
        locked_until = case
          when (
            case
              when private.legacy_claim_attempts.window_started_at < now() - interval '15 minutes'
                then 1
              else private.legacy_claim_attempts.attempts + 1
            end
          ) >= 5
            then now() + interval '15 minutes'
          else null
        end,
        last_attempt_at = now();

    return jsonb_build_object('ok', false, 'message', 'Dados de acesso invalidos.');
  end if;

  select email into v_email from auth.users where id = v_uid;

  update public.usuarios
  set auth_user_id = v_uid,
      email = v_email,
      senha = null,
      legacy_password_hash = null,
      legacy_claimed_at = now()
  where id = v_profile_id;

  delete from private.legacy_claim_attempts where auth_user_id = v_uid;

  return jsonb_build_object('ok', true, 'message', 'Acesso vinculado com sucesso.');
end;
$$;

create or replace function public.create_access_invite(p_profile_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
begin
  if v_uid is null or not private.has_permission('profissionais') then
    raise exception 'Acesso negado.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.usuarios
    where id = p_profile_id
      and auth_user_id is null
      and ativo
  ) then
    raise exception 'Perfil indisponivel para ativacao.' using errcode = '22023';
  end if;

  update private.access_invites
  set used_at = now()
  where profile_id = p_profile_id
    and used_at is null;

  v_code := upper(encode(extensions.gen_random_bytes(8), 'hex'));

  insert into private.access_invites (
    profile_id, code_hash, created_by, expires_at
  )
  values (
    p_profile_id,
    encode(extensions.digest(v_code, 'sha256'), 'hex'),
    v_uid,
    now() + interval '7 days'
  );

  return v_code;
end;
$$;

create or replace function public.claim_access_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_invite_id uuid;
  v_profile_id uuid;
  v_email text;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'message', 'Autenticacao obrigatoria.');
  end if;

  if exists (select 1 from public.usuarios where auth_user_id = v_uid) then
    return jsonb_build_object('ok', true, 'message', 'Acesso ja vinculado.');
  end if;

  select i.id, i.profile_id
  into v_invite_id, v_profile_id
  from private.access_invites i
  join public.usuarios u on u.id = i.profile_id
  where i.code_hash = encode(
      extensions.digest(upper(trim(p_code)), 'sha256'),
      'hex'
    )
    and i.used_at is null
    and i.expires_at > now()
    and u.auth_user_id is null
    and u.ativo
  for update of i;

  if v_invite_id is null then
    return jsonb_build_object('ok', false, 'message', 'Codigo invalido ou expirado.');
  end if;

  select email into v_email from auth.users where id = v_uid;

  update public.usuarios
  set auth_user_id = v_uid,
      email = v_email,
      senha = null,
      legacy_password_hash = null,
      legacy_claimed_at = now()
  where id = v_profile_id;

  update private.access_invites
  set used_at = now()
  where id = v_invite_id;

  return jsonb_build_object('ok', true, 'message', 'Acesso ativado com sucesso.');
end;
$$;

create or replace function public.get_horarios_ocupados(p_data date)
returns table (hora text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_data is null
     or p_data < (now() at time zone 'America/Sao_Paulo')::date
     or p_data > (now() at time zone 'America/Sao_Paulo')::date + 180 then
    raise exception 'Data fora do periodo permitido.' using errcode = '22023';
  end if;

  return query
  select a.hora
  from public.agendamentos a
  where a.data_agendamento = p_data
  order by a.hora;
end;
$$;

create or replace function public.criar_agendamento_publico(
  p_procedimento_id uuid,
  p_data date,
  p_hora text,
  p_nome text,
  p_whatsapp text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text := trim(coalesce(p_nome, ''));
  v_phone text := regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g');
  v_clinic_now timestamp := now() at time zone 'America/Sao_Paulo';
  v_contact_hash text;
  v_attempts integer;
  v_proc_nome text;
  v_duracao integer;
  v_blocks integer;
  v_start_hour integer;
  v_block_hour integer;
  v_slot text;
  v_patient_id uuid;
  v_group_id bigint;
  i integer;
begin
  if p_data is null
     or p_data < v_clinic_now::date
     or p_data > v_clinic_now::date + 180 then
    return jsonb_build_object('ok', false, 'message', 'Data indisponivel.');
  end if;

  if length(v_nome) < 3 or length(v_nome) > 120 or v_nome ~ '[<>]' then
    return jsonb_build_object('ok', false, 'message', 'Nome invalido.');
  end if;

  if length(v_phone) < 10 or length(v_phone) > 13 then
    return jsonb_build_object('ok', false, 'message', 'WhatsApp invalido.');
  end if;

  if p_hora is null or p_hora !~ '^[0-2][0-9]:00$' then
    return jsonb_build_object('ok', false, 'message', 'Horario invalido.');
  end if;

  v_contact_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');

  insert into private.public_booking_limits (
    contact_hash, attempts, window_started_at, last_attempt_at
  )
  values (v_contact_hash, 1, now(), now())
  on conflict (contact_hash) do update
  set attempts = case
        when private.public_booking_limits.window_started_at < now() - interval '1 hour'
          then 1
        else private.public_booking_limits.attempts + 1
      end,
      window_started_at = case
        when private.public_booking_limits.window_started_at < now() - interval '1 hour'
          then now()
        else private.public_booking_limits.window_started_at
      end,
      last_attempt_at = now()
  returning attempts into v_attempts;

  if v_attempts > 10 then
    return jsonb_build_object(
      'ok', false,
      'message', 'Limite de tentativas atingido. Tente novamente mais tarde.'
    );
  end if;

  select p.nome, p.duracao
  into v_proc_nome, v_duracao
  from public.procedimentos p
  where p.id = p_procedimento_id
    and p.status = 'Ativo';

  if v_proc_nome is null then
    return jsonb_build_object('ok', false, 'message', 'Procedimento indisponivel.');
  end if;

  v_blocks := greatest(1, ceil(v_duracao / 60.0)::integer);
  v_start_hour := split_part(p_hora, ':', 1)::integer;

  if p_data = v_clinic_now::date
     and v_start_hour <= extract(hour from v_clinic_now)::integer then
    return jsonb_build_object('ok', false, 'message', 'Horario indisponivel.');
  end if;

  -- Bloqueios por horario em ordem evitam corridas entre reservas simultaneas.
  for i in 0..v_blocks - 1 loop
    v_block_hour := v_start_hour + i;

    if v_block_hour < 8 or v_block_hour >= 18 or v_block_hour = 12 then
      return jsonb_build_object('ok', false, 'message', 'Horario indisponivel.');
    end if;

    v_slot := lpad(v_block_hour::text, 2, '0') || ':00';
    perform pg_advisory_xact_lock(
      hashtextextended(p_data::text || '|' || v_slot, 0)
    );
  end loop;

  for i in 0..v_blocks - 1 loop
    v_block_hour := v_start_hour + i;
    v_slot := lpad(v_block_hour::text, 2, '0') || ':00';

    if exists (
      select 1
      from public.agendamentos a
      where a.data_agendamento = p_data
        and a.hora = v_slot
    ) then
      return jsonb_build_object('ok', false, 'message', 'Horario acabou de ser ocupado.');
    end if;
  end loop;

  select p.id
  into v_patient_id
  from public.pacientes p
  where p.whatsapp_normalizado = v_phone
  order by p.created_at, p.id
  limit 1;

  v_group_id := nextval('public.agendamento_agrupador_seq'::regclass);

  begin
    if v_patient_id is null then
      insert into public.pacientes (nome, whatsapp, whatsapp_normalizado)
      values (v_nome, v_phone, v_phone)
      returning id into v_patient_id;
    end if;

    for i in 0..v_blocks - 1 loop
      v_block_hour := v_start_hour + i;
      v_slot := lpad(v_block_hour::text, 2, '0') || ':00';

      insert into public.agendamentos (
        id_agrupador,
        data_agendamento,
        hora,
        paciente_id,
        procedimento_id,
        paciente_nome,
        procedimento_nome,
        is_continuacao,
        created_by
      )
      values (
        v_group_id,
        p_data,
        v_slot,
        v_patient_id,
        p_procedimento_id,
        v_nome,
        v_proc_nome,
        i > 0,
        null
      );
    end loop;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'message', 'Horario acabou de ser ocupado.');
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'Agendamento criado com sucesso.',
    'id_agrupador', v_group_id,
    'procedimento', v_proc_nome
  );
end;
$$;

create or replace function public.criar_agendamento_interno(
  p_procedimento_id uuid,
  p_data date,
  p_hora text,
  p_paciente_id uuid default null,
  p_nome text default null,
  p_whatsapp text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_nome text := trim(coalesce(p_nome, ''));
  v_phone text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g'), '');
  v_clinic_now timestamp := now() at time zone 'America/Sao_Paulo';
  v_proc_nome text;
  v_duracao integer;
  v_blocks integer;
  v_start_hour integer;
  v_block_hour integer;
  v_slot text;
  v_patient_id uuid := p_paciente_id;
  v_group_id bigint;
  i integer;
begin
  if v_uid is null or not private.has_permission('agenda') then
    raise exception 'Acesso negado.' using errcode = '42501';
  end if;

  if p_data is null
     or p_data < v_clinic_now::date
     or p_data > v_clinic_now::date + 365 then
    return jsonb_build_object('ok', false, 'message', 'Data indisponivel.');
  end if;

  if p_hora is null
     or p_hora !~ '^[0-2][0-9]:00$'
     or split_part(p_hora, ':', 1)::integer > 23 then
    return jsonb_build_object('ok', false, 'message', 'Horario invalido.');
  end if;

  select p.nome, p.duracao
  into v_proc_nome, v_duracao
  from public.procedimentos p
  where p.id = p_procedimento_id
    and p.status = 'Ativo';

  if v_proc_nome is null then
    return jsonb_build_object('ok', false, 'message', 'Procedimento indisponivel.');
  end if;

  if v_patient_id is not null then
    select p.id, p.nome
    into v_patient_id, v_nome
    from public.pacientes p
    where p.id = v_patient_id;

    if v_patient_id is null then
      return jsonb_build_object('ok', false, 'message', 'Paciente nao encontrado.');
    end if;
  else
    if length(v_nome) < 3 or length(v_nome) > 120 or v_nome ~ '[<>]' then
      return jsonb_build_object('ok', false, 'message', 'Nome invalido.');
    end if;
  end if;

  v_blocks := greatest(1, ceil(v_duracao / 60.0)::integer);
  v_start_hour := split_part(p_hora, ':', 1)::integer;

  if p_data = v_clinic_now::date
     and v_start_hour <= extract(hour from v_clinic_now)::integer then
    return jsonb_build_object('ok', false, 'message', 'Horario indisponivel.');
  end if;

  for i in 0..v_blocks - 1 loop
    v_block_hour := v_start_hour + i;

    if v_block_hour > 23 then
      return jsonb_build_object('ok', false, 'message', 'O procedimento ultrapassa o fim do dia.');
    end if;

    v_slot := lpad(v_block_hour::text, 2, '0') || ':00';
    perform pg_advisory_xact_lock(
      hashtextextended(p_data::text || '|' || v_slot, 0)
    );
  end loop;

  for i in 0..v_blocks - 1 loop
    v_block_hour := v_start_hour + i;
    v_slot := lpad(v_block_hour::text, 2, '0') || ':00';

    if exists (
      select 1
      from public.agendamentos a
      where a.data_agendamento = p_data
        and a.hora = v_slot
    ) then
      return jsonb_build_object('ok', false, 'message', 'Horario acabou de ser ocupado.');
    end if;
  end loop;

  v_group_id := nextval('public.agendamento_agrupador_seq'::regclass);

  begin
    if v_patient_id is null then
      insert into public.pacientes (nome, whatsapp, whatsapp_normalizado)
      values (v_nome, p_whatsapp, v_phone)
      returning id into v_patient_id;
    end if;

    for i in 0..v_blocks - 1 loop
      v_block_hour := v_start_hour + i;
      v_slot := lpad(v_block_hour::text, 2, '0') || ':00';

      insert into public.agendamentos (
        id_agrupador,
        data_agendamento,
        hora,
        paciente_id,
        procedimento_id,
        paciente_nome,
        procedimento_nome,
        is_continuacao,
        created_by
      )
      values (
        v_group_id,
        p_data,
        v_slot,
        v_patient_id,
        p_procedimento_id,
        v_nome,
        v_proc_nome,
        i > 0,
        v_uid
      );
    end loop;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'message', 'Horario acabou de ser ocupado.');
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'Agendamento criado com sucesso.',
    'id_agrupador', v_group_id
  );
end;
$$;

-- Funcoes SECURITY DEFINER no schema publico nao herdam EXECUTE aberto.
revoke all on function public.claim_legacy_profile(text, text)
  from public, anon, authenticated;
revoke all on function public.create_access_invite(uuid)
  from public, anon, authenticated;
revoke all on function public.claim_access_invite(text)
  from public, anon, authenticated;
revoke all on function public.get_horarios_ocupados(date)
  from public, anon, authenticated;
revoke all on function public.criar_agendamento_publico(uuid, date, text, text, text)
  from public, anon, authenticated;
revoke all on function public.criar_agendamento_interno(uuid, date, text, uuid, text, text)
  from public, anon, authenticated;

grant execute on function public.claim_legacy_profile(text, text)
  to authenticated;
grant execute on function public.create_access_invite(uuid)
  to authenticated;
grant execute on function public.claim_access_invite(text)
  to authenticated;
grant execute on function public.get_horarios_ocupados(date)
  to anon, authenticated;
grant execute on function public.criar_agendamento_publico(uuid, date, text, text, text)
  to anon, authenticated;
grant execute on function public.criar_agendamento_interno(uuid, date, text, uuid, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Privilegios minimos e RLS
-- ---------------------------------------------------------------------------

revoke all on table public.usuarios from anon, authenticated;
revoke all on table public.pacientes from anon, authenticated;
revoke all on table public.procedimentos from anon, authenticated;
revoke all on table public.agendamentos from anon, authenticated;
revoke all on table public.anamneses from anon, authenticated;

grant select (
  id, nome, especialidade, nick, permissoes, created_at,
  auth_user_id, email, ativo, legacy_claimed_at
) on public.usuarios to authenticated;

grant insert (
  nome, especialidade, nick, permissoes, ativo
) on public.usuarios to authenticated;

grant update (
  nome, especialidade, nick, permissoes, ativo
) on public.usuarios to authenticated;

grant select, insert, update on public.pacientes to authenticated;
grant select on public.procedimentos to anon, authenticated;
grant insert, update on public.procedimentos to authenticated;
grant select, insert, delete on public.agendamentos to authenticated;
grant select, insert, update on public.anamneses to authenticated;

alter table public.usuarios enable row level security;
alter table public.pacientes enable row level security;
alter table public.procedimentos enable row level security;
alter table public.agendamentos enable row level security;
alter table public.anamneses enable row level security;

drop policy if exists usuarios_select_secure on public.usuarios;
create policy usuarios_select_secure
on public.usuarios
for select
to authenticated
using (
  auth_user_id = (select auth.uid())
  or (select private.has_permission('profissionais'))
);

drop policy if exists usuarios_insert_secure on public.usuarios;
create policy usuarios_insert_secure
on public.usuarios
for insert
to authenticated
with check ((select private.has_permission('profissionais')));

drop policy if exists usuarios_update_secure on public.usuarios;
create policy usuarios_update_secure
on public.usuarios
for update
to authenticated
using ((select private.has_permission('profissionais')))
with check ((select private.has_permission('profissionais')));

drop policy if exists pacientes_select_secure on public.pacientes;
create policy pacientes_select_secure
on public.pacientes
for select
to authenticated
using (
  (select private.has_permission('agenda'))
  or (select private.has_permission('pacientes'))
  or (select private.has_permission('documentos'))
);

drop policy if exists pacientes_insert_secure on public.pacientes;
create policy pacientes_insert_secure
on public.pacientes
for insert
to authenticated
with check (
  (select private.has_permission('agenda'))
  or (select private.has_permission('pacientes'))
);

drop policy if exists pacientes_update_secure on public.pacientes;
create policy pacientes_update_secure
on public.pacientes
for update
to authenticated
using ((select private.has_permission('pacientes')))
with check ((select private.has_permission('pacientes')));

drop policy if exists procedimentos_public_select on public.procedimentos;
create policy procedimentos_public_select
on public.procedimentos
for select
to anon, authenticated
using (status = 'Ativo');

drop policy if exists procedimentos_staff_select on public.procedimentos;
create policy procedimentos_staff_select
on public.procedimentos
for select
to authenticated
using ((select private.is_active_staff()));

drop policy if exists procedimentos_insert_secure on public.procedimentos;
create policy procedimentos_insert_secure
on public.procedimentos
for insert
to authenticated
with check ((select private.has_permission('procedimentos')));

drop policy if exists procedimentos_update_secure on public.procedimentos;
create policy procedimentos_update_secure
on public.procedimentos
for update
to authenticated
using ((select private.has_permission('procedimentos')))
with check ((select private.has_permission('procedimentos')));

drop policy if exists agendamentos_select_secure on public.agendamentos;
create policy agendamentos_select_secure
on public.agendamentos
for select
to authenticated
using (
  (select private.has_permission('agenda'))
  or (select private.has_permission('configuracoes'))
);

drop policy if exists agendamentos_insert_secure on public.agendamentos;
create policy agendamentos_insert_secure
on public.agendamentos
for insert
to authenticated
with check (
  (select private.has_permission('agenda'))
  and created_by = (select auth.uid())
);

drop policy if exists agendamentos_delete_secure on public.agendamentos;
create policy agendamentos_delete_secure
on public.agendamentos
for delete
to authenticated
using ((select private.has_permission('agenda')));

drop policy if exists anamneses_select_secure on public.anamneses;
create policy anamneses_select_secure
on public.anamneses
for select
to authenticated
using ((select private.has_permission('documentos')));

drop policy if exists anamneses_insert_secure on public.anamneses;
create policy anamneses_insert_secure
on public.anamneses
for insert
to authenticated
with check ((select private.has_permission('documentos')));

drop policy if exists anamneses_update_secure on public.anamneses;
create policy anamneses_update_secure
on public.anamneses
for update
to authenticated
using ((select private.has_permission('documentos')))
with check ((select private.has_permission('documentos')));

-- Evita que novas tabelas e funcoes sejam expostas automaticamente.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete, truncate, references, trigger
  on tables from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated;

commit;
