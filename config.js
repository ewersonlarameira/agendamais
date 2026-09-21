'use strict';

const SUPABASE_URL = 'https://xwtkfdfhmaaraodrusxx.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_Skl9u5WqpCxPSI2ad8fwhA_dkocWjiq';

window.supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY,
  {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
      flowType: 'pkce'
    }
  }
);
