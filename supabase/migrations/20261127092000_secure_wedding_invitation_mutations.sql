-- Prevent an owner from bypassing the recipient's explicit acceptance.
revoke insert on public.wedding_project_invitations from authenticated;
grant insert(project_id, inviter_user_id, invitee_email, role, can_view, can_upload, can_edit)
  on public.wedding_project_invitations to authenticated;
revoke update on public.wedding_project_invitations from authenticated;

create or replace function public.accept_wedding_project_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_row public.wedding_project_invitations;
begin
  update public.wedding_project_invitations
  set invitee_user_id = auth.uid(), status = 'accepted', accepted_at = now(), updated_at = now()
  where id = p_invitation_id and status = 'pending' and expires_at > now()
    and lower(invitee_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  returning * into v_row;
  if not found then raise exception 'Invitation not found, expired, or email does not match'; end if;
  return jsonb_build_object('ok', true, 'project_id', v_row.project_id, 'role', v_row.role,
    'can_view', v_row.can_view, 'can_upload', v_row.can_upload, 'can_edit', v_row.can_edit);
end;
$$;

create or replace function public.revoke_wedding_project_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_project_id uuid;
begin
  update public.wedding_project_invitations i
  set status = 'revoked', revoked_at = now(), updated_at = now()
  from public.wedding_projects p
  where i.id = p_invitation_id and p.id = i.project_id
    and p.owner_customer_id = auth.uid() and i.inviter_user_id = auth.uid()
    and i.status in ('pending', 'accepted')
  returning i.project_id into v_project_id;
  if v_project_id is null then raise exception 'Invitation not found or not revocable'; end if;
  return jsonb_build_object('ok', true, 'project_id', v_project_id);
end;
$$;

grant execute on function public.accept_wedding_project_invitation(uuid) to authenticated;
grant execute on function public.revoke_wedding_project_invitation(uuid) to authenticated;
