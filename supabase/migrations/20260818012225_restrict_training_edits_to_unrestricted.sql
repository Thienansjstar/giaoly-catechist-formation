-- Training credit now flows primarily through the Events/attendance system
-- (Program Coordinator / Tech Admin only). Direct manual edits to a
-- person's training list should follow the same rule, not the per-class
-- scoping that governs other fields -- otherwise a Class Coordinator could
-- free-text edit training records that conflict with the attendance-driven
-- source of truth.
drop policy if exists "person_training writable by own-class coordinators" on person_training;
create policy "person_training writable by unrestricted users" on person_training
  for all to authenticated
  using (public.has_unrestricted_access())
  with check (public.has_unrestricted_access());
