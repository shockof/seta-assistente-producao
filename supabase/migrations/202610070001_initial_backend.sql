-- Seta production assistant: shared teams, expense reports, receipts, and chat.
-- Run this migration in the Supabase SQL Editor while signed in as project owner.

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    email text not null default '',
    full_name text not null default '',
    phone_number text not null default '',
    profession text not null default 'Produtor geral',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.teams (
    id uuid primary key default gen_random_uuid(),
    name text not null check (length(trim(name)) > 0),
    description text not null default '',
    owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    created_at timestamptz not null default now()
);

create table public.team_members (
    id uuid primary key default gen_random_uuid(),
    team_id uuid not null references public.teams (id) on delete cascade,
    user_id uuid references auth.users (id) on delete set null,
    email text not null,
    full_name text not null,
    phone_number text not null default '',
    role text not null,
    released_budget numeric(12, 2) not null default 0 check (released_budget >= 0),
    is_active boolean not null default true,
    invited_by uuid not null references auth.users (id),
    created_at timestamptz not null default now(),
    constraint team_members_email_not_empty check (length(trim(email)) > 0),
    constraint team_members_name_not_empty check (length(trim(full_name)) > 0),
    constraint team_members_role_not_empty check (length(trim(role)) > 0)
);

create unique index team_members_team_email_unique
    on public.team_members (team_id, lower(email));
create unique index team_members_team_user_unique
    on public.team_members (team_id, user_id)
    where user_id is not null;
create index team_members_user_id_idx on public.team_members (user_id);

create table public.expenses (
    id uuid primary key default gen_random_uuid(),
    team_member_id uuid not null references public.team_members (id) on delete cascade,
    submitted_by uuid not null references auth.users (id),
    description text not null check (length(trim(description)) > 0),
    amount numeric(12, 2) not null check (amount > 0),
    created_at timestamptz not null default now()
);
create index expenses_member_created_idx
    on public.expenses (team_member_id, created_at desc);

create table public.expense_receipts (
    id uuid primary key default gen_random_uuid(),
    expense_id uuid not null references public.expenses (id) on delete cascade,
    storage_path text not null unique,
    file_name text not null,
    mime_type text not null default 'image/jpeg',
    uploaded_by uuid not null references auth.users (id),
    created_at timestamptz not null default now()
);
create index expense_receipts_expense_idx on public.expense_receipts (expense_id);

create table public.team_messages (
    id uuid primary key default extensions.gen_random_uuid(),
    team_id uuid not null references public.teams (id) on delete cascade,
    author_id uuid not null references auth.users (id),
    author_name text not null,
    body text not null check (length(trim(body)) > 0),
    created_at timestamptz not null default now()
);
create index team_messages_team_created_idx
    on public.team_messages (team_id, created_at);

-- The general producer owns the workspace; invited members get a user_id
-- only after they sign in with the invited, verified e-mail address.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, email, full_name, phone_number, profession)
    values (
        new.id,
        coalesce(new.email, ''),
        coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
        coalesce(new.raw_user_meta_data ->> 'phone_number', ''),
        coalesce(new.raw_user_meta_data ->> 'profession', 'Produtor geral')
    )
    on conflict (id) do update set
        email = excluded.email,
        full_name = case when excluded.full_name <> '' then excluded.full_name else public.profiles.full_name end,
        phone_number = case when excluded.phone_number <> '' then excluded.phone_number else public.profiles.phone_number end,
        updated_at = now();

    if new.email is not null and new.email_confirmed_at is not null then
        update public.team_members
        set user_id = new.id
        where user_id is null and lower(email) = lower(new.email);
    end if;
    return new;
end;
$$;

create or replace function public.link_verified_team_invites()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.email is not null and new.email_confirmed_at is not null then
        update public.team_members
        set user_id = new.id
        where user_id is null and lower(email) = lower(new.email);
    end if;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_auth_user();
create trigger on_auth_user_email_confirmed
    after update of email_confirmed_at on auth.users
    for each row
    when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
    execute procedure public.link_verified_team_invites();

create or replace function public.is_team_owner(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.teams t
        where t.id = target_team_id and t.owner_id = (select auth.uid())
    );
$$;

create or replace function public.can_access_team(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select public.is_team_owner(target_team_id)
        or exists (
        select 1 from public.team_members tm
            where tm.team_id = target_team_id and tm.user_id = (select auth.uid()) and tm.is_active
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
        join public.teams t on t.id = tm.team_id
        where e.id = target_expense_id
          and (e.submitted_by = (select auth.uid()) or t.owner_id = (select auth.uid()))
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
    );
end;
$$;

create or replace function public.can_view_expense_object(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    path_parts text[];
    target_expense_id uuid;
begin
    path_parts := string_to_array(object_name, '/');
    if coalesce(array_length(path_parts, 1), 0) < 3 then return false; end if;
    begin
        target_expense_id := path_parts[1]::uuid;
    exception when invalid_text_representation then
        return false;
    end;
    return public.can_view_expense(target_expense_id);
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.link_verified_team_invites() from public, anon, authenticated;
revoke all on function public.is_team_owner(uuid) from public, anon;
revoke all on function public.can_access_team(uuid) from public, anon;
revoke all on function public.can_view_expense(uuid) from public, anon;
revoke all on function public.can_upload_expense_object(text) from public, anon;
revoke all on function public.can_view_expense_object(text) from public, anon;
grant execute on function public.is_team_owner(uuid) to authenticated;
grant execute on function public.can_access_team(uuid) to authenticated;
grant execute on function public.can_view_expense(uuid) to authenticated;
grant execute on function public.can_upload_expense_object(text) to authenticated;
grant execute on function public.can_view_expense_object(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_receipts enable row level security;
alter table public.team_messages enable row level security;

revoke all on public.profiles, public.teams, public.team_members,
    public.expenses, public.expense_receipts, public.team_messages from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, phone_number, profession) on public.profiles to authenticated;
grant select, insert on public.teams to authenticated;
grant update (name, description) on public.teams to authenticated;
grant select on public.team_members to authenticated;
grant insert (team_id, email, full_name, phone_number, role, invited_by) on public.team_members to authenticated;
grant update (email, full_name, phone_number, role, released_budget, is_active) on public.team_members to authenticated;
grant select, insert on public.expenses to authenticated;
grant select, insert on public.expense_receipts to authenticated;
grant select, insert on public.team_messages to authenticated;

create policy "Users read their own profile"
    on public.profiles for select to authenticated
    using (id = (select auth.uid()));
create policy "Users update their own profile"
    on public.profiles for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

create policy "Team owners and members can read teams"
    on public.teams for select to authenticated
    using (public.can_access_team(id));
create policy "Authenticated users create their own teams"
    on public.teams for insert to authenticated
    with check (owner_id = (select auth.uid()));
create policy "Owners update teams"
    on public.teams for update to authenticated
    using (public.is_team_owner(id))
    with check (public.is_team_owner(id));
create policy "Members and owners read team members"
    on public.team_members for select to authenticated
    using ((user_id = (select auth.uid()) and is_active) or public.is_team_owner(team_id));
create policy "Owners add team members"
    on public.team_members for insert to authenticated
    with check (public.is_team_owner(team_id) and invited_by = (select auth.uid()) and user_id is null);
create policy "Owners update team members and budgets"
    on public.team_members for update to authenticated
    using (public.is_team_owner(team_id))
    with check (public.is_team_owner(team_id));
create policy "Submitters and team owners read expenses"
    on public.expenses for select to authenticated
    using (public.can_view_expense(id));
create policy "Team producers submit their own expenses"
    on public.expenses for insert to authenticated
    with check (
        submitted_by = (select auth.uid())
        and exists (
            select 1 from public.team_members tm
            where tm.id = team_member_id and tm.user_id = (select auth.uid()) and tm.is_active
        )
    );

create policy "Authorized users read receipt metadata"
    on public.expense_receipts for select to authenticated
    using (public.can_view_expense(expense_id));
create policy "Submitters add their receipt metadata"
    on public.expense_receipts for insert to authenticated
    with check (
        uploaded_by = (select auth.uid())
        and exists (
            select 1 from public.expenses e
            where e.id = expense_id and e.submitted_by = (select auth.uid())
        )
    );

create policy "Team members read team chat"
    on public.team_messages for select to authenticated
    using (public.can_access_team(team_id));
create policy "Team members send chat messages"
    on public.team_messages for insert to authenticated
    with check (author_id = (select auth.uid()) and public.can_access_team(team_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'expense-receipts',
    'expense-receipts',
    false,
    10485760,
    array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do update set
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Team owners and submitters view receipt images"
    on storage.objects for select to authenticated
    using (
        bucket_id = 'expense-receipts'
        and public.can_view_expense_object(name)
    );
create policy "Producers upload images for their expenses"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'expense-receipts'
        and public.can_upload_expense_object(name)
    );
