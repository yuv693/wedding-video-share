-- Public RSVP collection for published wedding invitations.
create table if not exists public.wedding_invitation_rsvps (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.digital_wedding_invitations(id) on delete cascade,
  guest_name text not null check (char_length(guest_name) between 1 and 100),
  guest_email text,
  attending boolean not null,
  guest_count smallint not null default 1 check (guest_count between 1 and 10),
  message text,
  created_at timestamptz not null default now()
);
create index if not exists wedding_invitation_rsvps_invitation_created_idx on public.wedding_invitation_rsvps(invitation_id, created_at desc);
alter table public.wedding_invitation_rsvps enable row level security;
grant select on public.wedding_invitation_rsvps to authenticated;
create policy "owners read invitation rsvps" on public.wedding_invitation_rsvps for select to authenticated
using (exists (select 1 from public.digital_wedding_invitations i where i.id = invitation_id and i.owner_customer_id = auth.uid()));
comment on table public.wedding_invitation_rsvps is 'Guest RSVP responses for published invitations. Public submissions are accepted only through the wedding-invitation-public Edge Function.';
