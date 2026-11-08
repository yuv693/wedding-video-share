-- Secure, one-time Google Drive connection handoff between consecutive anonymous wedding accounts.
create table if not exists app_private.google_drive_connection_transfers (
  token_hash text primary key,
  source_customer_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  target_customer_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint google_drive_connection_transfers_hash_check check (token_hash ~ '^[a-f0-9]{64}$')
);
alter table app_private.google_drive_connection_transfers enable row level security;

create or replace function public.gdrive_connection_transfer_create(p_source_customer_id uuid, p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_source_customer_id is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'INVALID_TRANSFER_REQUEST';
  end if;
  if not exists (
    select 1 from app_private.google_drive_connections
    where customer_id = p_source_customer_id and revoked_at is null
  ) then
    raise exception 'GOOGLE_DRIVE_CONNECTION_NOT_FOUND';
  end if;
  insert into app_private.google_drive_connection_transfers(token_hash, source_customer_id, expires_at)
  values (p_token_hash, p_source_customer_id, now() + interval '10 minutes');
  return true;
end;
$$;

create or replace function public.gdrive_connection_transfer_claim(p_token_hash text, p_target_customer_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source uuid;
begin
  if p_target_customer_id is null or p_token_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'INVALID_TRANSFER_REQUEST';
  end if;
  select source_customer_id into v_source
  from app_private.google_drive_connection_transfers
  where token_hash = p_token_hash
    and claimed_at is null
    and expires_at > now()
  for update;

  if v_source is null or v_source = p_target_customer_id then
    raise exception 'TRANSFER_TOKEN_INVALID_OR_EXPIRED';
  end if;

  insert into app_private.google_drive_connections
    (customer_id, google_account_email, encrypted_refresh_token, token_key_version,
     connected_at, last_verified_at, revoked_at, created_at, updated_at, google_drive_folder_id)
  select p_target_customer_id, google_account_email, encrypted_refresh_token, token_key_version,
         connected_at, last_verified_at, null, now(), now(), google_drive_folder_id
  from app_private.google_drive_connections
  where customer_id = v_source and revoked_at is null
  on conflict (customer_id) do update
    set google_account_email = excluded.google_account_email,
        encrypted_refresh_token = excluded.encrypted_refresh_token,
        token_key_version = excluded.token_key_version,
        connected_at = excluded.connected_at,
        last_verified_at = excluded.last_verified_at,
        revoked_at = null,
        updated_at = now(),
        google_drive_folder_id = coalesce(app_private.google_drive_connections.google_drive_folder_id, excluded.google_drive_folder_id);

  if not found then
    raise exception 'SOURCE_CONNECTION_NOT_FOUND';
  end if;

  update app_private.google_drive_connection_transfers
     set claimed_at = now(), target_customer_id = p_target_customer_id
   where token_hash = p_token_hash and claimed_at is null;
  if not found then
    raise exception 'TRANSFER_ALREADY_CLAIMED';
  end if;
  return true;
end;
$$;

revoke all on function public.gdrive_connection_transfer_create(uuid,text) from public, anon, authenticated;
revoke all on function public.gdrive_connection_transfer_claim(text,uuid) from public, anon, authenticated;
grant execute on function public.gdrive_connection_transfer_create(uuid,text) to service_role;
grant execute on function public.gdrive_connection_transfer_claim(text,uuid) to service_role;

delete from app_private.google_drive_connection_transfers where expires_at < now() - interval '1 day';
