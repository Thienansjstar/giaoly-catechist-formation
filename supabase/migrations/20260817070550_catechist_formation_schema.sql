-- Roles: the fixed formation stages (+ admin volunteer), with the static
-- framework content that used to live in the FRAMEWORK JS array.
create table roles (
  id text primary key,                 -- slug, e.g. 'assistant_catechist'
  name text not null unique,           -- display name, e.g. 'Assistant Catechist'
  stage text,                          -- 'One'..'Five', null for non-stage roles
  short_label text,
  tenure text,
  learn text,
  retreat text,
  habits jsonb not null default '[]',
  responsibilities jsonb not null default '[]',
  knowing jsonb not null default '{}',
  serving jsonb not null default '{}',
  sort_order smallint not null default 0
);

-- People: the volunteer roster.
create table people (
  id uuid primary key default gen_random_uuid(),
  legacy_num integer unique,           -- original "num" from the spreadsheet import
  first_name text not null,
  middle_name text,
  last_name text not null,
  birth_date date,
  class text,
  safe_environment boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index people_last_name_idx on people (last_name, first_name);

-- A person can hold multiple roles at once (seen in source data).
create table person_roles (
  person_id uuid not null references people(id) on delete cascade,
  role_id text not null references roles(id) on delete restrict,
  primary key (person_id, role_id)
);

-- Completed catechetical trainings per person (free text, matches source data).
create table person_training (
  person_id uuid not null references people(id) on delete cascade,
  training_title text not null,
  completed_at date,
  created_at timestamptz not null default now(),
  primary key (person_id, training_title)
);

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger people_set_updated_at
before update on people
for each row execute function set_updated_at();

-- RLS: public read (this is a parish roster page), authenticated write.
alter table roles enable row level security;
alter table people enable row level security;
alter table person_roles enable row level security;
alter table person_training enable row level security;

create policy "roles readable by everyone" on roles
  for select using (true);

create policy "people readable by everyone" on people
  for select using (true);
create policy "people writable by authenticated" on people
  for all to authenticated using (true) with check (true);

create policy "person_roles readable by everyone" on person_roles
  for select using (true);
create policy "person_roles writable by authenticated" on person_roles
  for all to authenticated using (true) with check (true);

create policy "person_training readable by everyone" on person_training
  for select using (true);
create policy "person_training writable by authenticated" on person_training
  for all to authenticated using (true) with check (true);
