import {backupHandler} from './handler.ts';
Deno.serve(backupHandler({url:Deno.env.get('SUPABASE_URL')||'',serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''}));
