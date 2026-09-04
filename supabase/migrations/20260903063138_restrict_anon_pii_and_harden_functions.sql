-- Hardening pass.
--
-- `people` was readable by anon over every column, including `email`.
-- Combined with anon-readable `person_roles`, that let anyone holding the
-- publishable key (which ships in index.html) list the Class Coordinators'
-- email addresses. With email auto-confirm enabled that was a full
-- account-takeover path: read a coordinator's address, sign up as them, and
-- the RLS policies -- which trust auth.jwt()->>'email' -- hand over write
-- access. Closing the read side removes the first link in that chain and is
-- worth keeping regardless of the auth setting.
--
-- The public roster page keeps working: loadPeopleFromSupabase() in
-- index.html selects an explicit column list that never included email or
-- auth_user_id.

-- 1. Column-level read grant for anon ---------------------------------------
-- Postgres has no "revoke one column from a table-level grant", so the
-- table-level grant is dropped and replaced with an explicit column list.
revoke select on public.people from anon;

grant select (
  id, legacy_num, first_name, middle_name, last_name,
  safe_environment, years_experience, created_at, updated_at
) on public.people to anon;

-- authenticated keeps full column access: loadCoordinatorInfo() filters on
-- auth_user_id, and coordinators legitimately need roster emails.
grant select on public.people to authenticated;

-- 2. roster view runs as the caller, not its creator ------------------------
-- Was SECURITY DEFINER, which bypassed the caller's RLS (linter 0010).
alter view public.roster set (security_invoker = true);

-- 3. Trigger-function search_path (linter 0011) -----------------------------
alter function public.set_updated_at() set search_path = public, pg_temp;

-- 4. Defence in depth: anon should not hold write grants at all -------------
-- anon held table-level INSERT/UPDATE on every table, leaving RLS as the
-- single thing between the public key and a roster rewrite. Nothing writes
-- while signed out, so drop the grants and make a future policy mistake
-- non-fatal rather than catastrophic. The audit trigger still records
-- changes: audit_trigger() is SECURITY DEFINER and inserts with the owner's
-- rights, not the caller's.
revoke insert, update, delete, truncate on all tables in schema public from anon;
