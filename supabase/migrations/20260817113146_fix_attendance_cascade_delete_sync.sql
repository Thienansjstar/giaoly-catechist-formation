-- Bug found in testing: when an entire training_event is deleted, the
-- ON DELETE CASCADE removal of its training_attendance rows fires this
-- trigger AFTER the parent training_events row is already gone, so
-- "select title from training_events where id = old.event_id" returns
-- NULL and the person_training cleanup silently no-ops. Fix: denormalize
-- the title onto training_attendance itself (stamped at insert time), so
-- delete never needs to look the parent event back up at all.
alter table training_attendance add column training_title text;

create or replace function public.stamp_attendance_title()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select title into new.training_title from training_events where id = new.event_id;
  return new;
end;
$$;

create trigger stamp_attendance_title_before_insert
before insert on training_attendance
for each row execute function public.stamp_attendance_title();

create or replace function public.sync_person_training_from_attendance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ev_date date;
begin
  if TG_OP = 'INSERT' then
    select event_date into ev_date from training_events where id = new.event_id;
    insert into person_training (person_id, training_title, completed_at)
    values (new.person_id, new.training_title, ev_date)
    on conflict (person_id, training_title) do update set completed_at = excluded.completed_at;
    return new;
  elsif TG_OP = 'DELETE' then
    if not exists (
      select 1 from training_attendance ta
      where ta.person_id = old.person_id
        and ta.training_title = old.training_title
        and ta.event_id <> old.event_id
    ) then
      delete from person_training where person_id = old.person_id and training_title = old.training_title;
    end if;
    return old;
  end if;
  return null;
end;
$$;
