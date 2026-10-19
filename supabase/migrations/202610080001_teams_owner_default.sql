-- Bind a new team's owner to the authenticated JWT in PostgreSQL itself.
-- The existing INSERT RLS policy still requires owner_id = auth.uid().
alter table public.teams
    alter column owner_id set default auth.uid();
