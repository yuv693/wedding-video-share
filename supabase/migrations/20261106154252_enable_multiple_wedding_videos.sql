alter table public.wedding_videos
  drop constraint if exists wedding_videos_order_id_key;

create or replace function public.gdrive_upload_session_save(
  p_order_id uuid,
  p_customer_id uuid,
  p_session_uri text,
  p_expected_size_bytes bigint,
  p_original_filename text,
  p_mime_type text
) returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.wedding_orders%rowtype;
begin
  select * into v_order
  from public.wedding_orders
  where id = p_order_id and customer_id = p_customer_id
  for update;

  if not found or v_order.upload_locked then
    return false;
  end if;

  insert into app_private.google_drive_upload_sessions(
    order_id, customer_id, session_uri, expected_size_bytes,
    original_filename, mime_type, expires_at
  )
  values (
    p_order_id, p_customer_id, p_session_uri, p_expected_size_bytes,
    p_original_filename, p_mime_type, now() + interval '7 days'
  )
  on conflict (order_id) do update
  set customer_id = excluded.customer_id,
      session_uri = excluded.session_uri,
      expected_size_bytes = excluded.expected_size_bytes,
      original_filename = excluded.original_filename,
      mime_type = excluded.mime_type,
      created_at = now(),
      expires_at = excluded.expires_at,
      completed_at = null,
      google_drive_file_id = null;

  return true;
end;
$function$;
