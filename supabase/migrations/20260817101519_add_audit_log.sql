-- Every coordinator can currently edit anyone/anything with zero record of
-- who changed what. This adds a generic audit trail on every writable
-- table, populated by trigger (not the app), so it can't be bypassed or
-- forgotten by future client code.
create table audit_log (
  id bigint generated always as identity primary key,
  changed_at timestamptz not null default now(),
  changed_by uuid,
  changed_by_email text,
  table_name text not null,
  operation text not null,
  old_data jsonb,
  new_data jsonb
);

alter table audit_log enable row level security;

-- Only coordinators can read the log; nobody writes to it directly via the
-- API (only the SECURITY DEFINER trigger function below does).
create policy "audit_log readable by class coordinators" on audit_log
  for select to authenticated using (public.is_signed_in_coordinator());

create or replace function public.audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  uemail text;
begin
  if uid is not null then
    select email into uemail from auth.users where id = uid;
  end if;
  insert into audit_log (changed_by, changed_by_email, table_name, operation, old_data, new_data)
  values (
    uid, uemail, TG_TABLE_NAME, TG_OP,
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('UPDATE','INSERT') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;

create trigger audit_people after insert or update or delete on people
  for each row execute function public.audit_trigger();
create trigger audit_person_roles after insert or update or delete on person_roles
  for each row execute function public.audit_trigger();
create trigger audit_person_training after insert or update or delete on person_training
  for each row execute function public.audit_trigger();
create trigger audit_class_assignments after insert or update or delete on class_assignments
  for each row execute function public.audit_trigger();
create trigger audit_roles after insert or update or delete on roles
  for each row execute function public.audit_trigger();
