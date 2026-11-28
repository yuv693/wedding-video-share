-- Cloud-backed source media for editor projects. Session URLs remain private.
create table if not exists public.wedding_editor_media_assets (
  id uuid primary key default gen_random_uuid(),
  editor_project_id uuid not null references public.wedding_editor_projects(id) on delete cascade,
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  drive_file_id text not null,
  original_filename text not null,
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes > 0 and file_size_bytes <= 40000000000),
  media_kind text not null check (media_kind in ('video','audio','image')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (editor_project_id, drive_file_id)
);

create index if not exists wedding_editor_media_assets_project_idx
  on public.wedding_editor_media_assets(editor_project_id, created_at)
  where deleted_at is null;

alter table public.wedding_editor_media_assets enable row level security;
revoke all on public.wedding_editor_media_assets from anon, authenticated;
grant select on public.wedding_editor_media_assets to authenticated;

drop policy if exists "project members read editor media metadata" on public.wedding_editor_media_assets;
create policy "project members read editor media metadata"
on public.wedding_editor_media_assets
for select to authenticated
using (
  exists (
    select 1 from public.wedding_projects p
    where p.id = project_id
      and (
        p.owner_customer_id = auth.uid()
        or exists (
          select 1 from public.wedding_project_invitations i
          where i.project_id = p.id
            and i.invitee_user_id = auth.uid()
            and i.status = 'accepted'
            and i.can_view = true
            and i.expires_at > now()
        )
      )
  )
);

create table if not exists app_private.wedding_editor_media_upload_sessions (
  session_id uuid primary key,
  editor_project_id uuid not null references public.wedding_editor_projects(id) on delete cascade,
  project_id uuid not null references public.wedding_projects(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  google_session_uri text not null,
  original_filename text not null,
  mime_type text not null,
  expected_size_bytes bigint not null check (expected_size_bytes > 0 and expected_size_bytes <= 40000000000),
  media_kind text not null check (media_kind in ('video','audio','image')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  completed_at timestamptz
);

create index if not exists wedding_editor_media_upload_sessions_expiry_idx
  on app_private.wedding_editor_media_upload_sessions(expires_at)
  where completed_at is null;

alter table app_private.wedding_editor_media_upload_sessions enable row level security;
revoke all on app_private.wedding_editor_media_upload_sessions from public, anon, authenticated;
