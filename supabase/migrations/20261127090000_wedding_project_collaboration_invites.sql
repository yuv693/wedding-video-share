-- Customer-controlled photographer/editor collaboration. Invitations are bound to the recipient's authenticated email.
create table if not exists public.wedding_project_invitations (
  id uuid primary key default gen_random_uuid(), project_id uuid not null references public.wedding_projects(id) on delete cascade,
  inviter_user_id uuid not null references auth.users(id) on delete cascade, invitee_email text not null,
  invitee_user_id uuid references auth.users(id) on delete set null,
  role text not null default 'photographer' check (role in ('photographer','editor','viewer')),
  can_view boolean not null default true, can_upload boolean not null default true, can_edit boolean not null default false,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null default (now() + interval '14 days'), accepted_at timestamptz, revoked_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint wedding_project_invitation_email_nonempty check (length(trim(invitee_email)) > 3)
);
create index if not exists wedding_project_invitations_project_idx on public.wedding_project_invitations(project_id,status);
create index if not exists wedding_project_invitations_email_idx on public.wedding_project_invitations(lower(invitee_email),status);
create unique index if not exists wedding_project_invitations_one_active_email on public.wedding_project_invitations(project_id,lower(invitee_email)) where status in ('pending','accepted');
alter table public.wedding_project_invitations enable row level security;
revoke all on public.wedding_project_invitations from anon;
grant select,insert on public.wedding_project_invitations to authenticated;
revoke update,delete on public.wedding_project_invitations from authenticated;
grant update(status,invitee_user_id,accepted_at,revoked_at,updated_at) on public.wedding_project_invitations to authenticated;
drop policy if exists "project owners create invitations" on public.wedding_project_invitations;
create policy "project owners create invitations" on public.wedding_project_invitations for insert to authenticated with check (inviter_user_id=auth.uid() and exists(select 1 from public.wedding_projects p where p.id=project_id and p.owner_customer_id=auth.uid()));
drop policy if exists "owners and invitees read invitations" on public.wedding_project_invitations;
create policy "owners and invitees read invitations" on public.wedding_project_invitations for select to authenticated using (inviter_user_id=auth.uid() or lower(invitee_email)=lower(coalesce(auth.jwt()->>'email','')) or invitee_user_id=auth.uid());
drop policy if exists "owners revoke invitations" on public.wedding_project_invitations;
create policy "owners revoke invitations" on public.wedding_project_invitations for update to authenticated using (inviter_user_id=auth.uid() and exists(select 1 from public.wedding_projects p where p.id=project_id and p.owner_customer_id=auth.uid())) with check (inviter_user_id=auth.uid() and status in ('pending','revoked','expired','accepted'));
drop policy if exists "invitees accept own invitations" on public.wedding_project_invitations;
create policy "invitees accept own invitations" on public.wedding_project_invitations for update to authenticated using (status='pending' and expires_at>now() and lower(invitee_email)=lower(coalesce(auth.jwt()->>'email',''))) with check (invitee_user_id=auth.uid() and status='accepted' and accepted_at is not null);
drop policy if exists "customers manage own wedding projects" on public.wedding_projects;
drop policy if exists "owners and accepted collaborators read projects" on public.wedding_projects;
create policy "owners and accepted collaborators read projects" on public.wedding_projects for select to authenticated using (wedding_projects.owner_customer_id=auth.uid() or exists(select 1 from public.wedding_project_invitations i where i.project_id=wedding_projects.id and i.invitee_user_id=auth.uid() and i.status='accepted' and i.can_view and i.expires_at>now()));
create policy "owners update projects" on public.wedding_projects for update to authenticated using(owner_customer_id=auth.uid()) with check(owner_customer_id=auth.uid());
create policy "owners insert projects" on public.wedding_projects for insert to authenticated with check(owner_customer_id=auth.uid());
create or replace function public.accept_wedding_project_invitation(p_invitation_id uuid) returns jsonb language plpgsql security invoker set search_path=public as $$ declare v_row public.wedding_project_invitations; begin update public.wedding_project_invitations set invitee_user_id=auth.uid(),status='accepted',accepted_at=now(),updated_at=now() where id=p_invitation_id and status='pending' and expires_at>now() and lower(invitee_email)=lower(coalesce(auth.jwt()->>'email','')) returning * into v_row; if not found then raise exception 'Invitation not found, expired, or email does not match'; end if; return jsonb_build_object('ok',true,'project_id',v_row.project_id,'role',v_row.role,'can_view',v_row.can_view,'can_upload',v_row.can_upload,'can_edit',v_row.can_edit); end; $$;
grant execute on function public.accept_wedding_project_invitation(uuid) to authenticated;
