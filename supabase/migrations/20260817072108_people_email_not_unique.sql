-- A person can legitimately have more than one roster row at this point in
-- history (e.g. coordinating multiple classes), so the same email can repeat.
-- (This constraint was later made moot entirely by
-- merge_duplicate_people_and_class_assignments, which gives each human
-- exactly one people row and moves "class" into class_assignments.)
drop index if exists people_email_idx;
create index people_email_idx on people (lower(email));
