-- Bug: enforce_coordinator_signup ran BEFORE INSERT on auth.users and tried
-- to set people.auth_user_id = new.id in the same statement. But
-- people.auth_user_id has a foreign key to auth.users(id), and the new
-- auth.users row doesn't exist yet during a BEFORE INSERT trigger — so
-- every signup (even valid coordinators) failed with a 500 FK violation.
-- Fix: BEFORE INSERT only validates and can abort the insert; a separate
-- AFTER INSERT trigger does the linking once the row actually exists.
create or replace function public.enforce_coordinator_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_class_coordinator(new.email) then
    raise exception 'Sign-up could not be completed for this email.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.link_coordinator_after_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update people
    set auth_user_id = new.id
    where lower(email) = lower(new.email)
      and auth_user_id is null;
  return new;
end;
$$;

drop trigger if exists link_coordinator_after_signup on auth.users;
create trigger link_coordinator_after_signup
after insert on auth.users
for each row execute function public.link_coordinator_after_signup();
