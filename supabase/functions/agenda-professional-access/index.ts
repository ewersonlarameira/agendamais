import {professionalAccessHandler} from './handler.ts';
Deno.serve(professionalAccessHandler({url:Deno.env.get('SUPABASE_URL')||'',serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||''}));
