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


-- Private upload-session operations are exposed only through service-role RPCs.
create or replace function public.wedding_editor_media_session_save(
  p_session_id uuid,
  p_editor_project_id uuid,
  p_project_id uuid,
  p_owner_customer_id uuid,
  p_google_session_uri text,
  p_original_filename text,
  p_mime_type text,
  p_expected_size_bytes bigint,
  p_media_kind text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_google_session_uri not like 'https://www.googleapis.com/%'
     or p_expected_size_bytes <= 0 or p_expected_size_bytes > 40000000000
     or p_media_kind not in ('video','audio','image') then
    return false;
  end if;
  insert into app_private.wedding_editor_media_upload_sessions(
    session_id, editor_project_id, project_id, owner_customer_id,
    google_session_uri, original_filename, mime_type, expected_size_bytes, media_kind
  ) values (
    p_session_id, p_editor_project_id, p_project_id, p_owner_customer_id,
    p_google_session_uri, p_original_filename, p_mime_type, p_expected_size_bytes, p_media_kind
  );
  return true;
end;
$$;

create or replace function public.wedding_editor_media_session_get(
  p_session_id uuid,
  p_editor_project_id uuid
) returns table (
  session_id uuid,
  editor_project_id uuid,
  project_id uuid,
  owner_customer_id uuid,
  google_session_uri text,
  original_filename text,
  mime_type text,
  expected_size_bytes bigint,
  media_kind text,
  expires_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select s.session_id, s.editor_project_id, s.project_id, s.owner_customer_id,
         s.google_session_uri, s.original_filename, s.mime_type,
         s.expected_size_bytes, s.media_kind, s.expires_at
  from app_private.wedding_editor_media_upload_sessions s
  where s.session_id = p_session_id
    and s.editor_project_id = p_editor_project_id
    and s.completed_at is null
    and s.expires_at > now()
  limit 1;
$$;

create or replace function public.wedding_editor_media_session_complete(
  p_session_id uuid,
  p_editor_project_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update app_private.wedding_editor_media_upload_sessions
     set completed_at = now()
   where session_id = p_session_id
     and editor_project_id = p_editor_project_id
     and completed_at is null;
  return found;
end;
$$;

create or replace function public.wedding_editor_media_ids_append(
  p_editor_project_id uuid,
  p_file_id text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.wedding_editor_projects
     set source_drive_file_ids = array(
       select distinct x
       from unnest(array_append(coalesce(source_drive_file_ids, '{}'::text[]), p_file_id)) as x
     ),
     updated_at = now()
   where id = p_editor_project_id;
  return found;
end;
$$;

revoke all on function public.wedding_editor_media_session_save(uuid,uuid,uuid,uuid,text,text,text,bigint,text) from public, anon, authenticated;
revoke all on function public.wedding_editor_media_session_get(uuid,uuid) from public, anon, authenticated;
revoke all on function public.wedding_editor_media_session_complete(uuid,uuid) from public, anon, authenticated;
revoke all on function public.wedding_editor_media_ids_append(uuid,text) from public, anon, authenticated;
grant execute on function public.wedding_editor_media_session_save(uuid,uuid,uuid,uuid,text,text,text,bigint,text) to service_role;
grant execute on function public.wedding_editor_media_session_get(uuid,uuid) to service_role;
grant execute on function public.wedding_editor_media_session_complete(uuid,uuid) to service_role;
grant execute on function public.wedding_editor_media_ids_append(uuid,text) to service_role;
