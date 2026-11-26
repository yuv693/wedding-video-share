-- Wedding Video Share product-module foundation.
-- This migration stores metadata and edit instructions only. Wedding media remains
-- in each customer's own Google Drive; no video/photo bytes are stored here.

-- Ensure the private schema exists on fresh Supabase projects before creating
-- token storage and helper functions. It is intentionally not exposed via PostgREST.
create schema if not exists app_private;
grant usage on schema app_private to authenticated;

create table if not exists public.wedding_projects (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  event_date date,
  venue text,
  status text not null default 'active'
    check (status in ('active','archived','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.photographer_studios (
  id uuid primary key default gen_random_uuid(),
  owner_customer_id uuid not null unique references auth.users(id) on delete cascade,
  studio_name text not null,
  contact_email text,
  contact_phone text,
  website_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.wedding_projects
  add column if not exists studio_id uuid references public.photographer_studios(id) on delete set null;

create table if not exists public.wedding_albums (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  guest_uploads_enabled boolean not null default false,
  guest_view_enabled boolean not null default true,
  downloads_enabled boolean not null default false,
  access_pin_hash text,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- References to customer Drive files only; never store media bytes or public Drive URLs.
create table if not exists public.wedding_album_items (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.wedding_albums(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  drive_file_id text not null,
  media_kind text not null check (media_kind in ('photo','video')),
  display_name text,
  created_at timestamptz not null default now(),
  unique (album_id, drive_file_id)
);

create table if not exists public.wedding_editor_projects (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'My wedding edit',
  timeline_json jsonb not null default '{"version":1,"clips":[],"audioTracks":[],"overlays":[],"transitions":[]}'::jsonb,
  source_drive_file_ids text[] not null default '{}',
  last_export_drive_file_id text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.wedding_ai_highlight_jobs (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  source_drive_file_ids text[] not null default '{}',
  status text not null default 'queued'
    check (status in ('queued','processing','awaiting_approval','approved','rejected','failed','completed')),
  suggested_timeline_json jsonb,
  customer_approved_at timestamptz,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.digital_wedding_invitations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  template_key text not null,
  event_details jsonb not null default '{}'::jsonb,
  rsvp_enabled boolean not null default false,
  public_slug text unique,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.wedding_reel_exports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  editor_project_id uuid references public.wedding_editor_projects(id) on delete set null,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  preset_key text not null check (preset_key in ('couple_entry','bride_groom_entry','ceremony','family_moments','teaser','custom')),
  aspect_ratio text not null default '9:16' check (aspect_ratio = '9:16'),
  edit_settings_json jsonb not null default '{}'::jsonb,
  export_drive_file_id text,
  status text not null default 'draft'
    check (status in ('draft','queued','rendering','ready','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Sensitive Instagram OAuth credentials are isolated in the private schema.
create table if not exists app_private.instagram_connections (
  customer_id uuid primary key references auth.users(id) on delete cascade,
  instagram_user_id text not null,
  username text,
  account_type text,
  encrypted_access_token text not null,
  encrypted_refresh_token text,
  token_expires_at timestamptz,
  granted_scopes text[] not null default '{}',
  connected_at timestamptz not null default now(),
  revoked_at timestamptz
);
alter table app_private.instagram_connections enable row level security;
revoke all on app_private.instagram_connections from public, anon, authenticated;

create table if not exists public.wedding_billing_events (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid references public.wedding_projects(id) on delete set null,
  provider text not null check (provider in ('razorpay','manual')),
  provider_event_id text,
  event_type text not null,
  amount_paise bigint not null default 0 check (amount_paise >= 0),
  currency text not null default 'INR',
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create table if not exists public.wedding_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_customer_id uuid references auth.users(id) on delete set null,
  project_id uuid references public.wedding_projects(id) on delete set null,
  event_type text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function app_private.owns_wedding_project(p_project_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.wedding_projects p
    where p.id = p_project_id and p.owner_customer_id = auth.uid()
  );
$$;
revoke all on function app_private.owns_wedding_project(uuid) from public, anon;
grant execute on function app_private.owns_wedding_project(uuid) to authenticated;

alter table public.wedding_projects enable row level security;
alter table public.photographer_studios enable row level security;
alter table public.wedding_albums enable row level security;
alter table public.wedding_album_items enable row level security;
alter table public.wedding_editor_projects enable row level security;
alter table public.wedding_ai_highlight_jobs enable row level security;
alter table public.digital_wedding_invitations enable row level security;
alter table public.wedding_reel_exports enable row level security;
alter table public.wedding_billing_events enable row level security;
alter table public.wedding_audit_events enable row level security;

create policy "customers manage own wedding projects"
on public.wedding_projects for all to authenticated
using (owner_customer_id = auth.uid())
with check (owner_customer_id = auth.uid());

create policy "customers manage own studio profile"
on public.photographer_studios for all to authenticated
using (owner_customer_id = auth.uid())
with check (owner_customer_id = auth.uid());

create policy "customers manage own wedding albums"
on public.wedding_albums for all to authenticated
using (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id))
with check (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id));

create policy "customers manage own album item references"
on public.wedding_album_items for all to authenticated
using (owner_customer_id = auth.uid() and exists (
  select 1 from public.wedding_albums a
  where a.id = album_id and a.owner_customer_id = auth.uid()
))
with check (owner_customer_id = auth.uid() and exists (
  select 1 from public.wedding_albums a
  where a.id = album_id and a.owner_customer_id = auth.uid()
));

create policy "customers manage own editor projects"
on public.wedding_editor_projects for all to authenticated
using (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id))
with check (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id));

create policy "customers manage own highlight jobs"
on public.wedding_ai_highlight_jobs for all to authenticated
using (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id))
with check (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id));

create policy "customers manage own invitations"
on public.digital_wedding_invitations for all to authenticated
using (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id))
with check (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id));

create policy "customers manage own reel exports"
on public.wedding_reel_exports for all to authenticated
using (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id))
with check (owner_customer_id = auth.uid() and app_private.owns_wedding_project(project_id));

create policy "customers read own billing events"
on public.wedding_billing_events for select to authenticated
using (customer_id = auth.uid());

create policy "customers read own audit events"
on public.wedding_audit_events for select to authenticated
using (actor_customer_id = auth.uid());

comment on table public.wedding_album_items is
  'Metadata references to files in the album owner customer Google Drive; no media bytes are stored here.';
comment on table public.wedding_editor_projects is
  'Editable timeline state only. Source and rendered media files remain in customer-owned Google Drive or on-device until explicitly exported.';
comment on table app_private.instagram_connections is
  'Encrypted OAuth token records. Never expose tokens to anon/authenticated clients; manage only through trusted server functions.';
