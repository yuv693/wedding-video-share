create or replace function public.wedding_album_guest_pin_required(p_token_hash text)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select (a.access_pin_enabled or a.access_pin_hash is not null)
 from public.wedding_albums a join app_private.wedding_album_guest_access g on g.album_id=a.id
 where g.token_hash=p_token_hash and g.revoked_at is null and a.revoked_at is null
 and (a.expires_at is null or a.expires_at>now())),false);
$$;
revoke all on function public.wedding_album_guest_pin_required(text) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_pin_required(text) to service_role;
