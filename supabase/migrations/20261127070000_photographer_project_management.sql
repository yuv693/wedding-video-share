-- Photographer Studio Portal project management fields.
-- These fields store customer contact details only; no media is stored here.
alter table public.wedding_projects
  add column if not exists client_name text,
  add column if not exists client_email text,
  add column if not exists client_phone text;

comment on column public.wedding_projects.client_name is
  'Customer contact name entered by the project owner.';
comment on column public.wedding_projects.client_email is
  'Customer contact email entered by the project owner.';
comment on column public.wedding_projects.client_phone is
  'Customer contact phone entered by the project owner.';
