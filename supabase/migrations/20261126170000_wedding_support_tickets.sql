create table if not exists public.wedding_support_tickets (
 id uuid primary key default gen_random_uuid(),
 owner_customer_id uuid not null references auth.users(id) on delete cascade,
 project_id uuid references public.wedding_projects(id) on delete set null,
 subject text not null check (char_length(subject) between 3 and 120),
 message text not null check (char_length(message) between 5 and 3000),
 status text not null default 'open' check (status in ('open','in_progress','resolved')),
 admin_response text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists wedding_support_tickets_status_created_idx on public.wedding_support_tickets(status,created_at desc);
alter table public.wedding_support_tickets enable row level security;
grant select,insert on public.wedding_support_tickets to authenticated;
drop policy if exists "customers read own wedding support tickets" on public.wedding_support_tickets;
create policy "customers read own wedding support tickets" on public.wedding_support_tickets for select to authenticated using(owner_customer_id=auth.uid());
drop policy if exists "customers create own wedding support tickets" on public.wedding_support_tickets;
create policy "customers create own wedding support tickets" on public.wedding_support_tickets for insert to authenticated with check(owner_customer_id=auth.uid() and (project_id is null or app_private.owns_wedding_project(project_id)));
