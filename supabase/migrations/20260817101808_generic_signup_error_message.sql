-- Previously the raised exception said "% is not on the coordinator
-- roster", explicitly confirming an email's non-coordinator status to
-- anyone who calls the Supabase Auth API directly (bypassing the app's
-- already-generic UI message). Not worth eliminating the enumeration
-- signal entirely here (that would mean silently fake-succeeding on every
-- signup, which just trades a low-severity leak for real UX confusion on
-- a small parish roster app) — but there's no reason to hand over more
-- detail than necessary in the one place that's cheap to fix.
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
  update people
    set auth_user_id = new.id
    where lower(email) = lower(new.email)
      and auth_user_id is null;
  return new;
end;
$$;
