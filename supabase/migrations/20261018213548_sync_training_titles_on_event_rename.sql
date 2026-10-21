-- training_events.title is the single source of truth for a training's name,
-- but two denormalized copies of it had drifted away.
--
-- 20260817113146 stamps the title onto training_attendance at insert time, and
-- sync_person_training_from_attendance() copies that stamp into
-- person_training. Nothing rewrote either copy when an event was renamed, so
-- dropping the "Catechist Formation Day: " prefix from four events left their
-- existing credits under the old spelling. knownTrainingTitles() in the app
-- unions credited titles with event titles, so the picker and the roster CSV
-- then showed the same training twice -- once per spelling.
--
-- Part A backfills from the event each credit came from rather than stripping
-- the prefix textually, so any future drift is corrected the same way. Part B
-- adds the missing rename propagation.

-- ---------------------------------------------------------------- Part A

-- Credit rows whose title no longer matches the event they came from.
-- Today: 47 rows across 4 titles (Building a Culture of Accompaniment 10,
-- Co-Teaching 16, Lesson Planning 17, The Dimensions of Formation 4).
create temporary table drifted on commit drop as
select distinct
  a.person_id,
  a.training_title as stale_title,
  t.title          as canonical_title,
  t.event_date
from training_attendance a
join training_events t on t.id = a.event_id
where a.training_title is distinct from t.title;

-- Credit under the current title. completed_at comes from the event date, the
-- same value sync_person_training_from_attendance() would have written.
insert into person_training (person_id, training_title, completed_at)
select person_id, canonical_title, event_date
from drifted
on conflict (person_id, training_title) do update
  set completed_at = coalesce(person_training.completed_at, excluded.completed_at);

-- Drop the stale credit, unless the person also attended some *other* event
-- whose current title really is that string -- two events may legitimately
-- share a name (Virtus Training is on the calendar twice), and that person's
-- credit is still earned. Scoped to the drifted titles so a hand-entered
-- credit with no event behind it is never touched.
delete from person_training pt
where pt.training_title in (select stale_title from drifted)
  and exists (
    select 1 from drifted d
    where d.person_id = pt.person_id
      and d.stale_title = pt.training_title
  )
  and not exists (
    select 1
    from training_attendance a
    join training_events t on t.id = a.event_id
    where a.person_id = pt.person_id
      and t.title = pt.training_title
  );

-- Resync the stamp the credits are derived from, so a later delete still
-- finds its credit by title.
update training_attendance a
set training_title = t.title
from training_events t
where t.id = a.event_id
  and a.training_title is distinct from t.title;

-- ---------------------------------------------------------------- Part B

create or replace function public.sync_titles_on_event_rename()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Give every attendee the new title.
  insert into person_training (person_id, training_title, completed_at)
  select a.person_id, new.title, new.event_date
  from training_attendance a
  where a.event_id = new.id
  on conflict (person_id, training_title) do update
    set completed_at = coalesce(person_training.completed_at, excluded.completed_at);

  -- Then retire the old one, keeping it for anyone who also attended another
  -- event still named that -- the same other-event check
  -- sync_person_training_from_attendance() makes before deleting a credit.
  delete from person_training pt
  where pt.training_title = old.title
    and exists (
      select 1 from training_attendance a
      where a.event_id = new.id
        and a.person_id = pt.person_id
    )
    and not exists (
      select 1
      from training_attendance a
      join training_events t on t.id = a.event_id
      where a.person_id = pt.person_id
        and t.id <> new.id
        and t.title = old.title
    );

  update training_attendance
  set training_title = new.title
  where event_id = new.id;

  return null;
end;
$$;

-- Pure trigger function, never called directly: no EXECUTE grant, per
-- 20260903063235.
revoke all on function public.sync_titles_on_event_rename() from public, anon, authenticated;

create trigger sync_titles_after_event_rename
after update of title on training_events
for each row
when (new.title is distinct from old.title)
execute function public.sync_titles_on_event_rename();
