-- Stable link between an auth.users identity and their roster row, instead
-- of comparing auth.jwt() ->> 'email' against people.email as text on every
-- request (fragile to case/whitespace drift and not indexed for a join).
alter table people add column auth_user_id uuid unique references auth.users(id) on delete set null;

-- Backfill: anyone who already has an auth account (only possible if they
-- passed the coordinator-email check at signup) gets linked retroactively.
update people p
set auth_user_id = u.id
from auth.users u
where lower(p.email) = lower(u.email)
  and p.auth_user_id is null;

-- Populate auth_user_id going forward, right after the coordinator-email
-- check passes, so every future signup is linked from the start.
create or replace function public.enforce_coordinator_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_class_coordinator(new.email) then
    raise exception 'Sign-up is restricted to Class Coordinators. % is not on the coordinator roster.', new.email
      using errcode = '42501';
  end if;
  update people
    set auth_user_id = new.id
    where lower(email) = lower(new.email)
      and auth_user_id is null;
  return new;
end;
$$;

-- Stable, indexed check: is the currently-authenticated user linked to a
-- people row that holds the class_coordinator role?
create or replace function public.is_signed_in_coordinator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from people p
    join person_roles pr on pr.person_id = p.id
    where p.auth_user_id = auth.uid()
      and pr.role_id = 'class_coordinator'
  );
$$;

-- Swap every write policy from the email-text check to the id-based one.
drop policy if exists "people writable by class coordinators" on people;
create policy "people writable by class coordinators" on people
  for all to authenticated
  using (public.is_signed_in_coordinator())
  with check (public.is_signed_in_coordinator());

drop policy if exists "person_roles writable by class coordinators" on person_roles;
create policy "person_roles writable by class coordinators" on person_roles
  for all to authenticated
  using (public.is_signed_in_coordinator())
  with check (public.is_signed_in_coordinator());

drop policy if exists "person_training writable by class coordinators" on person_training;
create policy "person_training writable by class coordinators" on person_training
  for all to authenticated
  using (public.is_signed_in_coordinator())
  with check (public.is_signed_in_coordinator());

drop policy if exists "roles writable by class coordinators" on roles;
create policy "roles writable by class coordinators" on roles
  for all to authenticated
  using (public.is_signed_in_coordinator())
  with check (public.is_signed_in_coordinator());

drop policy if exists "class_assignments writable by class coordinators" on class_assignments;
create policy "class_assignments writable by class coordinators" on class_assignments
  for all to authenticated
  using (public.is_signed_in_coordinator())
  with check (public.is_signed_in_coordinator());
