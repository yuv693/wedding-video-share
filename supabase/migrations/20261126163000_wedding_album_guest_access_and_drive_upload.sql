create table if not exists app_private.wedding_album_guest_access (
  album_id uuid primary key references public.wedding_albums(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
alter table app_private.wedding_album_guest_access enable row level security;
revoke all on app_private.wedding_album_guest_access from public, anon, authenticated;

create table if not exists app_private.wedding_album_guest_upload_sessions (
  session_id uuid primary key,
  album_id uuid not null references public.wedding_albums(id) on delete cascade,
  owner_customer_id uuid not null references auth.users(id) on delete cascade,
  google_session_uri text not null,
  expected_size_bytes bigint not null check (expected_size_bytes > 0 and expected_size_bytes <= 40000000000),
  mime_type text not null,
  display_name text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  completed_at timestamptz
);
alter table app_private.wedding_album_guest_upload_sessions enable row level security;
revoke all on app_private.wedding_album_guest_upload_sessions from public, anon, authenticated;

create or replace function public.wedding_album_guest_access_set(p_album_id uuid,p_owner_customer_id uuid,p_token_hash text)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if not exists(select 1 from public.wedding_albums a where a.id=p_album_id and a.owner_customer_id=p_owner_customer_id and a.revoked_at is null) then return false; end if;
  insert into app_private.wedding_album_guest_access(album_id,owner_customer_id,token_hash,created_at,revoked_at)
  values(p_album_id,p_owner_customer_id,p_token_hash,now(),null)
  on conflict(album_id) do update set owner_customer_id=excluded.owner_customer_id,token_hash=excluded.token_hash,created_at=now(),revoked_at=null;
  return true;
end;
$$;
revoke all on function public.wedding_album_guest_access_set(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_access_set(uuid,uuid,text) to service_role;

create or replace function public.wedding_album_guest_access_get(p_token_hash text)
returns table(album_id uuid,owner_customer_id uuid,title text,project_id uuid,guest_uploads_enabled boolean,guest_view_enabled boolean,downloads_enabled boolean,expires_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select a.id,a.owner_customer_id,a.title,a.project_id,a.guest_uploads_enabled,a.guest_view_enabled,a.downloads_enabled,a.expires_at
  from public.wedding_albums a join app_private.wedding_album_guest_access g on g.album_id=a.id
  where g.token_hash=p_token_hash and g.revoked_at is null and a.revoked_at is null
    and (a.expires_at is null or a.expires_at > now());
$$;
revoke all on function public.wedding_album_guest_access_get(text) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_access_get(text) to service_role;

create or replace function public.wedding_album_guest_access_revoke(p_album_id uuid,p_owner_customer_id uuid)
returns boolean language sql security definer set search_path = ''
as $$
  update app_private.wedding_album_guest_access set revoked_at=now()
  where album_id=p_album_id and owner_customer_id=p_owner_customer_id and revoked_at is null
  returning true;
$$;
revoke all on function public.wedding_album_guest_access_revoke(uuid,uuid) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_access_revoke(uuid,uuid) to service_role;

create or replace function public.wedding_album_guest_session_save(p_session_id uuid,p_album_id uuid,p_owner_customer_id uuid,p_google_session_uri text,p_expected_size_bytes bigint,p_mime_type text,p_display_name text)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if not exists(select 1 from public.wedding_albums a where a.id=p_album_id and a.owner_customer_id=p_owner_customer_id and a.guest_uploads_enabled and a.revoked_at is null) then return false; end if;
  insert into app_private.wedding_album_guest_upload_sessions(session_id,album_id,owner_customer_id,google_session_uri,expected_size_bytes,mime_type,display_name)
  values(p_session_id,p_album_id,p_owner_customer_id,p_google_session_uri,p_expected_size_bytes,p_mime_type,p_display_name);
  return true;
end;
$$;
revoke all on function public.wedding_album_guest_session_save(uuid,uuid,uuid,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_session_save(uuid,uuid,uuid,text,bigint,text,text) to service_role;

create or replace function public.wedding_album_guest_session_get(p_session_id uuid,p_album_id uuid)
returns table(owner_customer_id uuid,google_session_uri text,expected_size_bytes bigint,mime_type text,display_name text)
language sql stable security definer set search_path = ''
as $$
  select s.owner_customer_id,s.google_session_uri,s.expected_size_bytes,s.mime_type,s.display_name
  from app_private.wedding_album_guest_upload_sessions s
  where s.session_id=p_session_id and s.album_id=p_album_id and s.completed_at is null and s.expires_at>now();
$$;
revoke all on function public.wedding_album_guest_session_get(uuid,uuid) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_session_get(uuid,uuid) to service_role;

create or replace function public.wedding_album_guest_session_complete(p_session_id uuid,p_album_id uuid)
returns boolean language sql security definer set search_path = ''
as $$
  update app_private.wedding_album_guest_upload_sessions set completed_at=now()
  where session_id=p_session_id and album_id=p_album_id and completed_at is null returning true;
$$;
revoke all on function public.wedding_album_guest_session_complete(uuid,uuid) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_session_complete(uuid,uuid) to service_role;
