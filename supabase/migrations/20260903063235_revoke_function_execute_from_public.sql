-- Follow-up to 20260903063138.
--
-- That migration tried to close the RPC surface with
-- `revoke ... from anon, authenticated`, which did nothing: Postgres grants
-- EXECUTE on functions to PUBLIC by default and anon inherits it, so there
-- was no anon-specific grant to revoke. Verified after the fact --
-- POST /rest/v1/rpc/is_class_coordinator was still answering for
-- unauthenticated callers. The revoke has to name PUBLIC.

-- Pure trigger functions: never called directly. A trigger fires with the
-- table owner's rights and does not check the caller's EXECUTE bit, so
-- revoking here does not affect inserts or updates.
revoke all on function public.audit_trigger() from public, anon, authenticated;
revoke all on function public.enforce_coordinator_signup() from public, anon, authenticated;
revoke all on function public.link_coordinator_after_signup() from public, anon, authenticated;
revoke all on function public.stamp_attendance_title() from public, anon, authenticated;
revoke all on function public.sync_person_training_from_attendance() from public, anon, authenticated;

-- is_class_coordinator() is referenced by no policy -- only by the signup
-- trigger, which is SECURITY DEFINER. As an RPC it was an oracle for
-- "is this address a coordinator?", so it goes entirely.
revoke all on function public.is_class_coordinator(text) from public, anon, authenticated;

-- These four ARE referenced by policies on the authenticated side. Drop the
-- PUBLIC grant, then re-grant authenticated explicitly -- without EXECUTE a
-- signed-in coordinator's own queries would fail policy evaluation.
-- anon never reaches them: every anon-facing policy is `using (true)`.
revoke all on function public.can_edit_person(uuid) from public, anon;
revoke all on function public.coordinator_classes() from public, anon;
revoke all on function public.has_unrestricted_access() from public, anon;
revoke all on function public.is_signed_in_coordinator() from public, anon;

grant execute on function public.can_edit_person(uuid) to authenticated;
grant execute on function public.coordinator_classes() to authenticated;
grant execute on function public.has_unrestricted_access() to authenticated;
grant execute on function public.is_signed_in_coordinator() to authenticated;
