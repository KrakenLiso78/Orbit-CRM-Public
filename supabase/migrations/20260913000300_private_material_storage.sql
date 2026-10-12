-- Private material storage. Object names must begin with the authenticated owner UUID.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'orbit-materials',
  'orbit-materials',
  false,
  20971520,
  array[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists orbit_materials_owner_read on storage.objects;

create policy orbit_materials_owner_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'orbit-materials'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Uploads and deletes are intentionally unavailable to browser clients until
-- a narrow, audited material operation is implemented and tested.
