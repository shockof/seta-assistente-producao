-- Repair older project deployments where the owner default or INSERT policy
-- differs from the app's expected owner_id = auth.uid() check.
alter table public.teams alter column owner_id set default auth.uid();
grant select, insert on public.teams to authenticated;
drop policy if exists "Authenticated users create their own teams" on public.teams;
create policy "Authenticated users create their own teams"
    on public.teams for insert to authenticated
    with check (owner_id = (select auth.uid()));
