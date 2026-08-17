create or replace view roster as
select
  p.id as person_id,
  trim(concat_ws(' ', p.first_name, nullif(p.middle_name, ''), p.last_name)) as name,
  coalesce(
    (select string_agg(r.name, ', ' order by r.sort_order)
     from person_roles pr join roles r on r.id = pr.role_id
     where pr.person_id = p.id),
    ''
  ) as giaoly_role,
  p.class,
  p.safe_environment as safe_environment,
  coalesce(
    (select string_agg(pt.training_title, '; ' order by pt.training_title)
     from person_training pt
     where pt.person_id = p.id),
    ''
  ) as catechetical_training
from people p
order by p.legacy_num;

grant select on roster to anon, authenticated;
