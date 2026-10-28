import {masterCompanyCredentialsHandler} from './handler.ts';
Deno.serve(masterCompanyCredentialsHandler({url:Deno.env.get('SUPABASE_URL')||'',serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''}));
