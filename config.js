const SUPABASE_URL = 'https://xwtkfdfhmaaraodrusxx.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh3dGtmZGZobWFhcmFvZHJ1c3h4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk5NDgyNjIsImV4cCI6MjEwNTUyNDI2Mn0.2rpZVApvoN14cqL2Ny5KeFI2aXEtQI99MkVgYIQsfUw';

// Mudamos o nome para supabaseClient para evitar conflitos
const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
