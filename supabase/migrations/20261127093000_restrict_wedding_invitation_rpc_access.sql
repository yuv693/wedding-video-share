revoke all on function public.accept_wedding_project_invitation(uuid) from public, anon;
revoke all on function public.revoke_wedding_project_invitation(uuid) from public, anon;
grant execute on function public.accept_wedding_project_invitation(uuid) to authenticated;
grant execute on function public.revoke_wedding_project_invitation(uuid) to authenticated;
