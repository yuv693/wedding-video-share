insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('wedding-invitation-assets', 'wedding-invitation-assets', true, 12582912, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 12582912,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "customers upload their wedding invitation photos" on storage.objects;
create policy "customers upload their wedding invitation photos"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'wedding-invitation-assets'
  and split_part(name, '/', 1) = auth.uid()::text
  and (storage.extension(name) in ('jpg','jpeg','png','webp'))
);

drop policy if exists "customers update their wedding invitation photos" on storage.objects;
create policy "customers update their wedding invitation photos"
on storage.objects for update to authenticated
using (bucket_id = 'wedding-invitation-assets' and split_part(name, '/', 1) = auth.uid()::text)
with check (bucket_id = 'wedding-invitation-assets' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists "customers delete their wedding invitation photos" on storage.objects;
create policy "customers delete their wedding invitation photos"
on storage.objects for delete to authenticated
using (bucket_id = 'wedding-invitation-assets' and split_part(name, '/', 1) = auth.uid()::text);
