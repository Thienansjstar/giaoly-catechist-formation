-- Backfilled to match production. This change was applied to the remote
-- database on 2026-08-24 but never committed, so the repo could not rebuild
-- the schema from scratch. Recovered from the live column definition.
alter table people add column if not exists years_experience text;
