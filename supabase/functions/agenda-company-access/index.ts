import {companyAccessHandler} from './handler.ts';
// Service role is a built-in Edge secret. It never enters Sites runtime, browser or source.
Deno.serve(companyAccessHandler({url:Deno.env.get('SUPABASE_URL')||'',serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''}));
