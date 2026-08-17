alter table people add column email text;
create unique index people_email_idx on people (lower(email)) where email is not null;
