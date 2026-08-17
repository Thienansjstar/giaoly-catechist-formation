create or replace function public.is_class_coordinator(check_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from person_roles pr
    join people p on p.id = pr.person_id
    where pr.role_id = 'class_coordinator'
      and lower(p.email) = lower(check_email)
  );
$$;

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
  return new;
end;
$$;

drop trigger if exists restrict_signup_to_coordinators on auth.users;
create trigger restrict_signup_to_coordinators
before insert on auth.users
for each row execute function public.enforce_coordinator_signup();

-- Replace blanket "authenticated" write policies with coordinator-checked ones.
drop policy if exists "people writable by authenticated" on people;
drop policy if exists "person_roles writable by authenticated" on person_roles;
drop policy if exists "person_training writable by authenticated" on person_training;

create policy "people writable by class coordinators" on people
  for all to authenticated
  using (public.is_class_coordinator(auth.jwt() ->> 'email'))
  with check (public.is_class_coordinator(auth.jwt() ->> 'email'));

create policy "person_roles writable by class coordinators" on person_roles
  for all to authenticated
  using (public.is_class_coordinator(auth.jwt() ->> 'email'))
  with check (public.is_class_coordinator(auth.jwt() ->> 'email'));

create policy "person_training writable by class coordinators" on person_training
  for all to authenticated
  using (public.is_class_coordinator(auth.jwt() ->> 'email'))
  with check (public.is_class_coordinator(auth.jwt() ->> 'email'));

create policy "roles writable by class coordinators" on roles
  for all to authenticated
  using (public.is_class_coordinator(auth.jwt() ->> 'email'))
  with check (public.is_class_coordinator(auth.jwt() ->> 'email'));
