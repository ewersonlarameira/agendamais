-- One consistent, size-limited business snapshot, available exclusively to Master.
-- Auth, Storage binaries, VAPID keys and browser subscriptions are intentionally excluded.
create function app_private.backup_export() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare tab text;rows jsonb;tables jsonb:='{}';size_bytes bigint:=0;part_bytes bigint;allowed text[]:=array['platform_admins','plans','tenants','licenses','memberships','settings','professionals','services','customers','appointments','whatsapp_templates','financial_entries','audit_logs'];
begin
 if auth.uid() is null or not app_private.master() then raise exception 'Acesso exclusivo Master.';end if;
 foreach tab in array allowed loop
  execute format('select coalesce(sum(octet_length(to_jsonb(t)::text)+2),0) from public.%I t',tab) into part_bytes;
  size_bytes:=size_bytes+part_bytes;
  if size_bytes>8388608 then raise exception 'O volume excede o limite de exportação pelo navegador (8 MB). Utilize backup PostgreSQL para exportar a base completa.';end if;
 end loop;
 foreach tab in array allowed loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',tab) into rows;
  tables:=tables||jsonb_build_object(tab,rows);
 end loop;
 return jsonb_build_object('format','agenda-business-snapshot','version',2,'exported_at',now(),'tables',tables,
  'excludes',jsonb_build_array('auth_accounts_and_passwords','storage_binaries','private_secrets','push_devices_and_queue'),
  'restore_notice','Dados de negócio. A recuperação completa requer backup PostgreSQL e dos arquivos do Storage em ambiente separado.');
end $$;
revoke all on function app_private.backup_export() from public,anon,authenticated;
grant execute on function app_private.backup_export() to authenticated;
create function public.agenda_backup_export() returns jsonb language sql stable security invoker set search_path='' as $$select app_private.backup_export()$$;
revoke all on function public.agenda_backup_export() from public,anon,authenticated;
grant execute on function public.agenda_backup_export() to authenticated;
