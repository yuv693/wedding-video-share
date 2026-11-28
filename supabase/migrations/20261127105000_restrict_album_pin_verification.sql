revoke all on function public.wedding_album_guest_pin_required(text) from public,anon,authenticated;
revoke all on function public.wedding_album_guest_pin_verify(text,text) from public,anon,authenticated;
grant execute on function public.wedding_album_guest_pin_required(text) to service_role;
grant execute on function public.wedding_album_guest_pin_verify(text,text) to service_role;
