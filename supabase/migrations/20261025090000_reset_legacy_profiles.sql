-- =============================================================================
-- BuildMatch · 00 · OPTIONAL reset of the earlier prototype `profiles` table
-- -----------------------------------------------------------------------------
-- Run this ONLY if your project still has the first draft of `public.profiles`
-- (role check contractor/client/admin + signup/email/updated_at triggers).
-- It removes that table and any trigger on auth.users whose function lives in
-- the public schema, so the new signup trigger in migration 02 is the only one.
--
-- Skip this file on a fresh Supabase project.
-- Existing auth users are back-filled into the new profiles table by
-- migration 02 if their metadata role is 'contractor' or 'supplier'.
-- =============================================================================

do $$
declare
  t record;
begin
  for t in
    select tg.tgname, p.oid::regprocedure as fn
    from pg_trigger tg
    join pg_proc p      on p.oid = tg.tgfoid
    join pg_namespace n on n.oid = p.pronamespace
    where tg.tgrelid = 'auth.users'::regclass
      and not tg.tgisinternal
      and n.nspname = 'public'
  loop
    -- identifiers are quoted with %I / regprocedure, no user input involved
    execute format('drop trigger if exists %I on auth.users', t.tgname);
    execute format('drop function if exists %s cascade', t.fn);
  end loop;
end
$$;

drop table if exists public.profiles cascade;
