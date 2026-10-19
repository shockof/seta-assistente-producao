-- Annual Seta Pro plan (R$ 59.88 billed once per year).
-- Do not insert subscriptions from a client. Only the verified Stripe webhook
-- uses the service role to keep this table current.

create table if not exists public.billing_subscriptions (
    user_id uuid primary key references auth.users(id) on delete cascade,
    stripe_customer_id text unique,
    stripe_subscription_id text unique,
    stripe_price_id text,
    status text not null default 'inactive',
    current_period_end timestamptz,
    cancel_at_period_end boolean not null default false,
    updated_at timestamptz not null default now()
);

alter table public.billing_subscriptions enable row level security;
revoke all on public.billing_subscriptions from anon, authenticated;
grant select on public.billing_subscriptions to authenticated;
drop policy if exists "Users read their billing status" on public.billing_subscriptions;
create policy "Users read their billing status"
    on public.billing_subscriptions for select to authenticated
    using (user_id = (select auth.uid()));

create or replace function public.has_active_subscription(target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.billing_subscriptions s
        where s.user_id = target_user_id
          and s.status in ('active', 'trialing')
          and (s.current_period_end is null or s.current_period_end > now())
    );
$$;

create or replace function public.team_subscription_active(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.teams t
        where t.id = target_team_id
          and public.has_active_subscription(t.owner_id)
    );
$$;

create or replace function public.can_access_team(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select public.team_subscription_active(target_team_id)
       and (
           public.is_team_owner(target_team_id)
           or exists (
               select 1 from public.team_members tm
               where tm.team_id = target_team_id
                 and tm.user_id = (select auth.uid())
                 and tm.is_active
           )
       );
$$;

create or replace function public.can_view_expense(target_expense_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.expenses e
        join public.team_members tm on tm.id = e.team_member_id
        where e.id = target_expense_id
          and public.can_access_team(tm.team_id)
          and (e.submitted_by = (select auth.uid()) or public.is_team_owner(tm.team_id))
    );
$$;

create or replace function public.can_upload_expense_object(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    path_parts text[];
    target_expense_id uuid;
    path_user_id uuid;
begin
    path_parts := string_to_array(object_name, '/');
    if coalesce(array_length(path_parts, 1), 0) < 3 then return false; end if;
    begin
        target_expense_id := path_parts[1]::uuid;
        path_user_id := path_parts[2]::uuid;
    exception when invalid_text_representation then
        return false;
    end;
    return path_user_id = (select auth.uid()) and exists (
        select 1 from public.expenses e
        join public.team_members tm on tm.id = e.team_member_id
        where e.id = target_expense_id
          and e.submitted_by = (select auth.uid())
          and tm.user_id = (select auth.uid())
          and public.can_access_team(tm.team_id)
    );
end;
$$;

revoke all on function public.has_active_subscription(uuid) from public, anon;
revoke all on function public.team_subscription_active(uuid) from public, anon;
grant execute on function public.has_active_subscription(uuid) to authenticated;
grant execute on function public.team_subscription_active(uuid) to authenticated;
grant execute on function public.can_upload_expense_object(text) to authenticated;

-- Team access is granted only while the workspace owner's annual plan is current.
drop policy if exists "Team owners and members can read teams" on public.teams;
drop policy if exists "Authenticated users create their own teams" on public.teams;
drop policy if exists "Owners update teams" on public.teams;
drop policy if exists "Active subscribers and members read teams" on public.teams;
drop policy if exists "Active subscribers create their own teams" on public.teams;
drop policy if exists "Active subscribers update their own teams" on public.teams;
create policy "Active subscribers and members read teams"
    on public.teams for select to authenticated
    using (public.can_access_team(id));
create policy "Active subscribers create their own teams"
    on public.teams for insert to authenticated
    with check (owner_id = (select auth.uid()) and public.has_active_subscription((select auth.uid())));
create policy "Active subscribers update their own teams"
    on public.teams for update to authenticated
    using (public.is_team_owner(id) and public.has_active_subscription((select auth.uid())))
    with check (public.is_team_owner(id) and public.has_active_subscription((select auth.uid())));
grant delete on public.teams to authenticated;
drop policy if exists "Active subscribers delete their own teams" on public.teams;
create policy "Active subscribers delete their own teams"
    on public.teams for delete to authenticated
    using (public.is_team_owner(id) and public.has_active_subscription((select auth.uid())));

drop policy if exists "Members and owners read team members" on public.team_members;
drop policy if exists "Owners add team members" on public.team_members;
drop policy if exists "Owners update team members and budgets" on public.team_members;
drop policy if exists "Subscribed team members read team members" on public.team_members;
drop policy if exists "Subscribed owners add team members" on public.team_members;
drop policy if exists "Subscribed owners update team members and budgets" on public.team_members;
create policy "Subscribed team members read team members"
    on public.team_members for select to authenticated
    using (public.can_access_team(team_id));
create policy "Subscribed owners add team members"
    on public.team_members for insert to authenticated
    with check (public.is_team_owner(team_id)
        and public.has_active_subscription((select auth.uid()))
        and invited_by = (select auth.uid()) and user_id is null);
create policy "Subscribed owners update team members and budgets"
    on public.team_members for update to authenticated
    using (public.is_team_owner(team_id) and public.has_active_subscription((select auth.uid())))
    with check (public.is_team_owner(team_id) and public.has_active_subscription((select auth.uid())));

drop policy if exists "Team producers submit their own expenses" on public.expenses;
drop policy if exists "Subscribed team producers submit expenses" on public.expenses;
create policy "Subscribed team producers submit expenses"
    on public.expenses for insert to authenticated
    with check (
        submitted_by = (select auth.uid())
        and exists (
            select 1 from public.team_members tm
            where tm.id = team_member_id and tm.user_id = (select auth.uid())
              and tm.is_active and public.can_access_team(tm.team_id)
        )
    );

drop policy if exists "Submitters add their receipt metadata" on public.expense_receipts;
drop policy if exists "Subscribed submitters add receipt metadata" on public.expense_receipts;
create policy "Subscribed submitters add receipt metadata"
    on public.expense_receipts for insert to authenticated
    with check (
        uploaded_by = (select auth.uid())
        and exists (
            select 1 from public.expenses e
            join public.team_members tm on tm.id = e.team_member_id
            where e.id = expense_id and e.submitted_by = (select auth.uid())
              and public.can_access_team(tm.team_id)
        )
    );

drop policy if exists "Team members send chat messages" on public.team_messages;
drop policy if exists "Subscribed team members send chat messages" on public.team_messages;
create policy "Subscribed team members send chat messages"
    on public.team_messages for insert to authenticated
    with check (author_id = (select auth.uid()) and public.can_access_team(team_id));

-- Replacing the helpers also secures private receipt downloads and uploads.
