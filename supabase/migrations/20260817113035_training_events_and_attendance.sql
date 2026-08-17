-- A scheduled training session. title deliberately reuses the same free-text
-- vocabulary as person_training.training_title (e.g. "Co-Teaching") so
-- attendance flows straight into the existing per-person training list.
create table training_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_date date,
  description text,
  created_at timestamptz not null default now()
);

create table training_attendance (
  event_id uuid not null references training_events(id) on delete cascade,
  person_id uuid not null references people(id) on delete cascade,
  marked_at timestamptz not null default now(),
  primary key (event_id, person_id)
);

alter table training_events enable row level security;
alter table training_attendance enable row level security;

create policy "training_events readable by everyone" on training_events
  for select using (true);
create policy "training_events writable by unrestricted users" on training_events
  for all to authenticated
  using (public.has_unrestricted_access())
  with check (public.has_unrestricted_access());

create policy "training_attendance readable by everyone" on training_attendance
  for select using (true);
create policy "training_attendance writable by unrestricted users" on training_attendance
  for all to authenticated
  using (public.has_unrestricted_access())
  with check (public.has_unrestricted_access());

create trigger audit_training_events after insert or update or delete on training_events
  for each row execute function public.audit_trigger();
create trigger audit_training_attendance after insert or update or delete on training_attendance
  for each row execute function public.audit_trigger();

-- Marking attendance automatically credits the person with that training
-- (this is the actual "automatically updates the database" requirement --
-- implemented as a trigger, not client-side dual writes, so it can't drift
-- out of sync with what the UI happens to do).
create or replace function public.sync_person_training_from_attendance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ev_title text;
  ev_date date;
begin
  if TG_OP = 'INSERT' then
    select title, event_date into ev_title, ev_date from training_events where id = new.event_id;
    insert into person_training (person_id, training_title, completed_at)
    values (new.person_id, ev_title, ev_date)
    on conflict (person_id, training_title) do update set completed_at = excluded.completed_at;
    return new;
  elsif TG_OP = 'DELETE' then
    select title into ev_title from training_events where id = old.event_id;
    -- Only remove the credit if no OTHER event with the same title still
    -- has an attendance record for this person (the same topic can be
    -- offered more than once).
    if not exists (
      select 1 from training_attendance ta
      join training_events te on te.id = ta.event_id
      where ta.person_id = old.person_id
        and te.title = ev_title
        and ta.event_id <> old.event_id
    ) then
      delete from person_training where person_id = old.person_id and training_title = ev_title;
    end if;
    return old;
  end if;
  return null;
end;
$$;

create trigger sync_person_training_after_attendance
after insert or delete on training_attendance
for each row execute function public.sync_person_training_from_attendance();
