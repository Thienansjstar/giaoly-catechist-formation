-- 1. New table: a person can be assigned to multiple classes.
create table class_assignments (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references people(id) on delete cascade,
  class text not null,
  unique (person_id, class)
);
alter table class_assignments enable row level security;
create policy "class_assignments readable by everyone" on class_assignments
  for select using (true);
create policy "class_assignments writable by class coordinators" on class_assignments
  for all to authenticated
  using (public.is_class_coordinator(auth.jwt() ->> 'email'))
  with check (public.is_class_coordinator(auth.jwt() ->> 'email'));

-- 2. Map every duplicate-email person row to one canonical row (lowest legacy_num wins).
create temporary table canonical_map as
select p.id as old_id,
       first_value(p.id) over (partition by lower(p.email) order by p.legacy_num) as canonical_id
from people p
where p.email is not null
  and lower(p.email) in (
    select lower(email) from people where email is not null group by lower(email) having count(*) > 1
  );

-- 3. Backfill class_assignments for everyone, folding duplicates onto their canonical id.
insert into class_assignments (person_id, class)
select coalesce(cm.canonical_id, p.id), p.class
from people p
left join canonical_map cm on cm.old_id = p.id
where p.class is not null
on conflict (person_id, class) do nothing;

-- 4. Fold person_roles / person_training onto the canonical id.
insert into person_roles (person_id, role_id)
select cm.canonical_id, pr.role_id
from person_roles pr
join canonical_map cm on cm.old_id = pr.person_id
on conflict do nothing;

insert into person_training (person_id, training_title)
select cm.canonical_id, pt.training_title
from person_training pt
join canonical_map cm on cm.old_id = pt.person_id
on conflict do nothing;

-- 5. safe_environment: true if true on ANY of the duplicate rows.
update people p
set safe_environment = true
where p.id in (
  select cm.canonical_id from canonical_map cm
  join people dup on dup.id = cm.old_id
  where dup.safe_environment = true
);

-- 6. Drop the now-merged duplicate rows (cascades their now-redundant person_roles/person_training/class_assignments rows).
delete from people
where id in (select old_id from canonical_map where old_id <> canonical_id);

-- 7. Roster view currently depends on people.class; drop it so the column can be dropped.
drop view if exists roster;

-- 8. class now lives only in class_assignments.
alter table people drop column class;

-- 9. Recreate roster view: class becomes an aggregated list.
create view roster as
select
  p.id as person_id,
  trim(concat_ws(' ', p.first_name, nullif(p.middle_name, ''), p.last_name)) as name,
  coalesce(
    (select string_agg(r.name, ', ' order by r.sort_order)
     from person_roles pr join roles r on r.id = pr.role_id
     where pr.person_id = p.id),
    ''
  ) as giaoly_role,
  coalesce(
    (select string_agg(ca.class, ', ' order by ca.class)
     from class_assignments ca where ca.person_id = p.id),
    ''
  ) as class,
  p.safe_environment,
  coalesce(
    (select string_agg(pt.training_title, '; ' order by pt.training_title)
     from person_training pt where pt.person_id = p.id),
    ''
  ) as catechetical_training
from people p
order by p.legacy_num;

grant select on roster to anon, authenticated;
