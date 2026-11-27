create or replace function public.accept_wedding_project_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_row public.wedding_project_invitations; v_email text; v_confirmed boolean;
begin
 select lower(u.email),(u.email_confirmed_at is not null) into v_email,v_confirmed from auth.users u where u.id=auth.uid();
 if auth.uid() is null or not coalesce(v_confirmed,false) then raise exception 'Please verify the invited email address before accepting'; end if;
 update public.wedding_project_invitations set invitee_user_id=auth.uid(),status='accepted',accepted_at=now(),expires_at='infinity'::timestamptz,updated_at=now()
 where id=p_invitation_id and status='pending' and invitee_user_id is null and expires_at>now() and lower(invitee_email)=v_email
 returning * into v_row;
 if not found then raise exception 'Invitation not found, expired, or email does not match'; end if;
 return jsonb_build_object('ok',true,'project_id',v_row.project_id,'role',v_row.role,'can_view',v_row.can_view,'can_upload',v_row.can_upload,'can_edit',v_row.can_edit);
end; $$;
revoke all on function public.accept_wedding_project_invitation(uuid) from public,anon;
grant execute on function public.accept_wedding_project_invitation(uuid) to authenticated;
