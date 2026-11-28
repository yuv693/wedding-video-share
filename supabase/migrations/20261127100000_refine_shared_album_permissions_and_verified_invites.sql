create or replace function app_private.can_view_wedding_project(p_project_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.wedding_projects p where p.id=p_project_id and p.owner_customer_id=auth.uid())
  or exists (select 1 from public.wedding_project_invitations i where i.project_id=p_project_id and i.invitee_user_id=auth.uid() and i.status='accepted' and i.can_view and i.expires_at>now());
$$;

drop policy if exists "owners and uploaders manage wedding albums" on public.wedding_albums;
drop policy if exists "owners and uploaders manage album item references" on public.wedding_album_items;

create policy "owners and viewers read wedding albums" on public.wedding_albums for select to authenticated
using (owner_customer_id=auth.uid() or (app_private.can_view_wedding_project(project_id) and owner_customer_id=(select p.owner_customer_id from public.wedding_projects p where p.id=project_id)));
create policy "owners and uploaders create wedding albums" on public.wedding_albums for insert to authenticated
with check (app_private.can_upload_wedding_project(project_id) and owner_customer_id=(select p.owner_customer_id from public.wedding_projects p where p.id=project_id));
create policy "owners update wedding albums" on public.wedding_albums for update to authenticated
using (owner_customer_id=auth.uid())
with check (owner_customer_id=auth.uid() and owner_customer_id=(select p.owner_customer_id from public.wedding_projects p where p.id=project_id));
create policy "owners delete wedding albums" on public.wedding_albums for delete to authenticated using (owner_customer_id=auth.uid());

create policy "owners and viewers read album item references" on public.wedding_album_items for select to authenticated
using (owner_customer_id=auth.uid() or exists(select 1 from public.wedding_albums a where a.id=album_id and app_private.can_view_wedding_project(a.project_id) and owner_customer_id=a.owner_customer_id));
create policy "owners and uploaders create album item references" on public.wedding_album_items for insert to authenticated
with check (exists(select 1 from public.wedding_albums a where a.id=album_id and app_private.can_upload_wedding_project(a.project_id) and owner_customer_id=a.owner_customer_id));
create policy "owners update album item references" on public.wedding_album_items for update to authenticated using(owner_customer_id=auth.uid()) with check(owner_customer_id=auth.uid());
create policy "owners delete album item references" on public.wedding_album_items for delete to authenticated using(owner_customer_id=auth.uid());

create or replace function public.accept_wedding_project_invitation(p_invitation_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_row public.wedding_project_invitations; v_email text; v_confirmed boolean;
begin
  select lower(u.email),(u.email_confirmed_at is not null) into v_email,v_confirmed from auth.users u where u.id=auth.uid();
  if auth.uid() is null or not coalesce(v_confirmed,false) then raise exception 'Please verify the invited email address before accepting'; end if;
  update public.wedding_project_invitations set invitee_user_id=auth.uid(),status='accepted',accepted_at=now(),updated_at=now()
  where id=p_invitation_id and status='pending' and invitee_user_id is null and expires_at>now() and lower(invitee_email)=v_email
  returning * into v_row;
  if not found then raise exception 'Invitation not found, expired, or email does not match'; end if;
  return jsonb_build_object('ok',true,'project_id',v_row.project_id,'role',v_row.role,'can_view',v_row.can_view,'can_upload',v_row.can_upload,'can_edit',v_row.can_edit);
end;
$$;
revoke all on function public.accept_wedding_project_invitation(uuid) from public,anon;
grant execute on function public.accept_wedding_project_invitation(uuid) to authenticated;
