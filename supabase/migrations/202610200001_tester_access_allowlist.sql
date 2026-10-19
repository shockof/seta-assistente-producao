-- Admin-managed free tester access. This table is intentionally inaccessible
-- to anon/authenticated clients; only trusted SQL/service-role administration
-- can grant or revoke test access.
create table if not exists public.billing_test_access (
    user_id uuid primary key references auth.users (id) on delete cascade,
    granted_at timestamptz not null default now()
);

alter table public.billing_test_access enable row level security;
revoke all on public.billing_test_access from public, anon, authenticated;

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
    ) or exists (
        select 1 from public.billing_test_access a
        where a.user_id = target_user_id
    );
$$;

revoke all on function public.has_active_subscription(uuid) from public, anon;
grant execute on function public.has_active_subscription(uuid) to authenticated;
