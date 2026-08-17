-- Coordinators could previously edit anyone/anything once signed in. This
-- scopes writes to only people who share at least one class with the
-- signed-in coordinator.
create or replace function public.coordinator_classes()
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select ca.class
  from people p
  join class_assignments ca on ca.person_id = p.id
  where p.auth_user_id = auth.uid();
$$;

create or replace function public.can_edit_person(target_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_signed_in_coordinator()
     and exists (
       select 1 from class_assignments ca
       where ca.person_id = target_person_id
         and ca.class in (select public.coordinator_classes())
     );
$$;

-- people: can only update a person already in one of your classes.
-- (INSERT is a no-op in practice -- a brand-new person has no class_assignments
-- yet, so can_edit_person is false for any id that doesn't already exist.)
drop policy if exists "people writable by class coordinators" on people;
create policy "people writable by own-class coordinators" on people
  for all to authenticated
  using (public.can_edit_person(id))
  with check (public.can_edit_person(id));

drop policy if exists "person_roles writable by class coordinators" on person_roles;
create policy "person_roles writable by own-class coordinators" on person_roles
  for all to authenticated
  using (public.can_edit_person(person_id))
  with check (public.can_edit_person(person_id));

drop policy if exists "person_training writable by class coordinators" on person_training;
create policy "person_training writable by own-class coordinators" on person_training
  for all to authenticated
  using (public.can_edit_person(person_id))
  with check (public.can_edit_person(person_id));

-- class_assignments: can modify/remove an assignment for someone already in
-- your class; can add a NEW assignment either for someone already in your
-- class, or to bring someone into one of your own classes for the first time.
drop policy if exists "class_assignments writable by class coordinators" on class_assignments;
create policy "class_assignments writable by own-class coordinators" on class_assignments
  for all to authenticated
  using (public.can_edit_person(person_id))
  with check (
    public.can_edit_person(person_id)
    or class in (select public.coordinator_classes())
  );

-- The formation framework (roles table) isn't tied to any one class -- take
-- coordinator write access away entirely rather than trying to force it
-- into a per-lop model. Nothing in the app writes to this table today.
drop policy if exists "roles writable by class coordinators" on roles;
