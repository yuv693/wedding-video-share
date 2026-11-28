revoke all on function app_private.can_view_wedding_project(uuid) from public,anon;
revoke all on function app_private.can_upload_wedding_project(uuid) from public,anon;
revoke all on function app_private.can_edit_wedding_project(uuid) from public,anon;
grant execute on function app_private.can_view_wedding_project(uuid) to authenticated,service_role;
grant execute on function app_private.can_upload_wedding_project(uuid) to authenticated,service_role;
grant execute on function app_private.can_edit_wedding_project(uuid) to authenticated,service_role;
