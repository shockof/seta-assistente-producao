-- Private Seta administrator allowlist.
-- The allowlist is private; add the owner through the Supabase SQL Editor after
-- applying this migration. Admin data access runs only in the Edge Function.
create table if not exists public.app_admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    created_at timestamptz not null default now()
);

alter table public.app_admins enable row level security;
revoke all on public.app_admins from public, anon, authenticated;
