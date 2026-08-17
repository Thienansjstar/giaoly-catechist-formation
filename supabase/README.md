# Supabase schema

Project ref: `lrrmasbimmzfgkbqvsae`.

`migrations/` mirrors the exact history applied to the live database
(check with the Supabase MCP `list_migrations` tool, or `supabase
migration list` if you link the CLI to this project — the timestamps
match 1:1).

**This folder reproduces the schema, not the data.** The 100+ roster
rows (names, birth dates, emails, training records) were imported once
from `catechist.xlsx` / the original dashboard's embedded JSON via
one-off `INSERT` statements, not tracked migrations — roster data lives
only in the live database from here on and is edited through the app
itself (or directly via SQL) by Class Coordinators.

To apply these migrations to a fresh project: run them in order,
lowest timestamp first. `20260817070550_catechist_formation_schema.sql`
must run before everything else; the rest are strictly sequential
(each one alters what the previous one created).
