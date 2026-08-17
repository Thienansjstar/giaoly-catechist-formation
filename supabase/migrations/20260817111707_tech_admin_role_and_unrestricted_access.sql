-- New role for whoever maintains the app/database itself, distinct from
-- the ministry roles.
insert into roles (id, name, sort_order) values ('tech_admin', 'Tech Admin', 100);

-- Program Coordinators and Tech Admins get unrestricted edit access;
-- Class Coordinators stay scoped to their own class (can_edit_person, below).
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
    where pr.role_id in ('class_coordinator', 'program_coordinator', 'tech_admin')
      and lower(p.email) = lower(check_email)
  );
$$;

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
      and pr.role_id in ('class_coordinator', 'program_coordinator', 'tech_admin')
  );
$$;

create or replace function public.has_unrestricted_access()
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
      and pr.role_id in ('program_coordinator', 'tech_admin')
  );
$$;

create or replace function public.can_edit_person(target_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_signed_in_coordinator()
     and (
       public.has_unrestricted_access()
       or exists (
         select 1 from class_assignments ca
         where ca.person_id = target_person_id
           and ca.class in (select public.coordinator_classes())
       )
     );
$$;

-- Program Coordinators / Tech Admins can maintain the formation framework
-- content too (Class Coordinators still cannot -- it isn't tied to a class).
create policy "roles writable by unrestricted users" on roles
  for all to authenticated
  using (public.has_unrestricted_access())
  with check (public.has_unrestricted_access());

-- Data fix: Rosie Dau is the actual Program Coordinator/BPV lead (her
-- "class" was literally the string "Program Coordinator" from the original
-- import, not a real Lop) -- she was mistagged as class_coordinator because
-- the spreadsheet import didn't distinguish the two.
delete from person_roles
where person_id = (select id from people where legacy_num = 36)
  and role_id = 'class_coordinator';
insert into person_roles (person_id, role_id)
select id, 'program_coordinator' from people where legacy_num = 36
on conflict do nothing;
