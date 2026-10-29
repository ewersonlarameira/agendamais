-- Public commercial projection only. Business/customer tables remain private.
create function app_private.public_plans() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'amount',amount,'months',months,'description',description) order by amount,months,name,id),'[]'::jsonb)
 from public.plans where active and deleted_at is null
$$;
revoke all on function app_private.public_plans() from public;
grant execute on function app_private.public_plans() to anon,authenticated;
create function public.agenda_public_plans() returns jsonb language sql stable security invoker set search_path='' as $$select app_private.public_plans()$$;
revoke all on function public.agenda_public_plans() from public;
grant execute on function public.agenda_public_plans() to anon,authenticated;
