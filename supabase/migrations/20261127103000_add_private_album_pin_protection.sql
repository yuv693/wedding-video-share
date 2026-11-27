alter table public.wedding_albums add column if not exists access_pin_enabled boolean not null default false;
create table if not exists app_private.wedding_album_pin_attempts(token_hash text primary key,attempt_count integer not null default 0,locked_until timestamptz,updated_at timestamptz not null default now());
alter table app_private.wedding_album_pin_attempts enable row level security;
revoke all on app_private.wedding_album_pin_attempts from public,anon,authenticated;

create or replace function public.wedding_album_guest_pin_set(p_album_id uuid,p_pin text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_pin is not null and p_pin !~ '^\d{4,8}$' then raise exception 'PIN_MUST_BE_4_TO_8_DIGITS'; end if;
 update public.wedding_albums set access_pin_hash=case when p_pin is null or p_pin='' then null else extensions.crypt(p_pin,extensions.gen_salt('bf',10)) end,
 access_pin_enabled=(p_pin is not null and p_pin<>''),updated_at=now()
 where id=p_album_id and owner_customer_id=auth.uid() and revoked_at is null;
 return found;
end; $$;

create or replace function public.wedding_album_guest_pin_required(p_token_hash text)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select a.access_pin_enabled from public.wedding_albums a join app_private.wedding_album_guest_access g on g.album_id=a.id
 where g.token_hash=p_token_hash and g.revoked_at is null and a.revoked_at is null and (a.expires_at is null or a.expires_at>now())),false);
$$;

create or replace function public.wedding_album_guest_pin_verify(p_token_hash text,p_pin text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_hash text; v_locked timestamptz; v_count integer;
begin
 select a.access_pin_hash into v_hash from public.wedding_albums a join app_private.wedding_album_guest_access g on g.album_id=a.id
 where g.token_hash=p_token_hash and g.revoked_at is null and a.revoked_at is null and (a.expires_at is null or a.expires_at>now());
 if not found then return false; end if;
 select locked_until,attempt_count into v_locked,v_count from app_private.wedding_album_pin_attempts where token_hash=p_token_hash for update;
 if v_locked is not null and v_locked>now() then return false; end if;
 if v_hash is null then return true; end if;
 if p_pin ~ '^\d{4,8}$' and extensions.crypt(p_pin,v_hash)=v_hash then delete from app_private.wedding_album_pin_attempts where token_hash=p_token_hash; return true; end if;
 insert into app_private.wedding_album_pin_attempts(token_hash,attempt_count,locked_until,updated_at) values(p_token_hash,1,null,now())
 on conflict(token_hash) do update set
 attempt_count=case when app_private.wedding_album_pin_attempts.locked_until is not null and app_private.wedding_album_pin_attempts.locked_until<=now() then 1 else app_private.wedding_album_pin_attempts.attempt_count+1 end,
 locked_until=case when (case when app_private.wedding_album_pin_attempts.locked_until is not null and app_private.wedding_album_pin_attempts.locked_until<=now() then 1 else app_private.wedding_album_pin_attempts.attempt_count+1 end)>=5 then now()+interval '15 minutes' else null end,
 updated_at=now();
 return false;
end; $$;
revoke all on function public.wedding_album_guest_pin_set(uuid,text) from public,anon;
revoke all on function public.wedding_album_guest_pin_required(text) from public,anon;
revoke all on function public.wedding_album_guest_pin_verify(text,text) from public,anon;
grant execute on function public.wedding_album_guest_pin_set(uuid,text) to authenticated;
grant execute on function public.wedding_album_guest_pin_required(text) to service_role;
grant execute on function public.wedding_album_guest_pin_verify(text,text) to service_role;
