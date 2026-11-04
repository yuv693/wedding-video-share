-- Align the upload ceiling with the app's 40 GB decimal limit and add
-- explicit consent for deleting the customer-owned Google Drive copy.
alter table public.wedding_videos
  drop constraint if exists wedding_videos_file_size_bytes_check;
alter table public.wedding_videos
  add constraint wedding_videos_file_size_bytes_check
  check (file_size_bytes > 0 and file_size_bytes <= 40000000000);

alter table app_private.google_drive_upload_sessions
  drop constraint if exists google_drive_upload_sessions_expected_size_bytes_check;
alter table app_private.google_drive_upload_sessions
  add constraint google_drive_upload_sessions_expected_size_bytes_check
  check (expected_size_bytes > 0 and expected_size_bytes <= 40000000000);

alter table public.wedding_videos
  add column if not exists auto_delete_consent_at timestamptz;

comment on column public.wedding_videos.auto_delete_consent_at is
  'Customer consent timestamp for automatic deletion of the customer-owned Google Drive copy after a server-verified complete receiver transfer.';

create or replace function app_private.notify_customer_download_completed()
returns trigger
language plpgsql
set search_path to 'pg_catalog', 'public', 'app_private'
as $function$
begin
  if new.status='completed'
     and new.completed_at is not null
     and new.verified_at is not null
     and new.bytes_transferred=new.bytes_expected
     and new.transfer_verified=true
     and (tg_op='INSERT' or old.status is distinct from 'completed') then
    insert into public.customer_notifications
      (customer_id,order_id,source_download_id,notification_type,title,message)
    select o.customer_id,o.id,new.id,
      'receiver_download_completed',
      'Wedding video download completed',
      'The server verified that the full video was streamed. Your Google Drive copy is automatically deleted only if you gave consent; otherwise it remains saved.'
    from public.wedding_orders o
    where o.id=new.order_id
    on conflict (source_download_id) do nothing;
  end if;
  return new;
end;
$function$;
