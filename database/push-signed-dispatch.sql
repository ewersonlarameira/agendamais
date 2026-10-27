-- Protect transport headers with short-lived HMAC signatures; no reusable secret leaves the private schema.
create or replace function app_private.kick_push() returns void language plpgsql security definer set search_path='' as $$
declare token text;origin text;stamp text:=floor(extract(epoch from clock_timestamp()))::bigint::text;nonce text:=replace(gen_random_uuid()::text,'-','');signature text;
begin
 delete from app_private.push_deliveries where created_at<now()-interval '7 days' and state<>'pending';
 update app_private.push_deliveries set state='failed',finished_at=now() where state='pending' and (attempts>=6 or created_at<now()-interval '1 day');
 if not exists(select 1 from app_private.push_deliveries where state='pending' and available_at<=now()) then return;end if;
 select value into token from app_private.secrets where key='push_dispatch';select value into origin from app_private.secrets where key='push_function_url';
 if token is null or origin is null then return;end if;
 -- pg_net transport tables have platform-managed grants. Never put a reusable secret in them.
 signature:=encode(extensions.hmac('agenda-push:'||stamp||':'||nonce||':dispatch',token,'sha256'),'hex');
 perform net.http_post(url:=origin,headers:=jsonb_build_object('Content-Type','application/json','x-agenda-push',signature,'x-agenda-timestamp',stamp,'x-agenda-nonce',nonce),body:='{}'::jsonb,timeout_milliseconds:=10000);
exception when others then
 -- Provider/dispatch outages never roll back a customer's booking. Cron retries the durable queue.
 return;
end $$;

