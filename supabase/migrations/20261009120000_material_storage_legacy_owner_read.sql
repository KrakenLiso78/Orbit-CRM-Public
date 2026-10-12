-- Preserve owner read access to imported material objects whose historical
-- paths predate the owner-UUID prefix. New browser uploads remain unavailable.

drop policy if exists orbit_materials_owner_read on storage.objects;

create policy orbit_materials_owner_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'orbit-materials'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.material_files linked_file
      where linked_file.owner_id = (select auth.uid())
        and linked_file.storage_bucket = bucket_id
        and linked_file.storage_object_path = name
    )
  )
);

comment on policy orbit_materials_owner_read on storage.objects is
  'Owner read access for UUID-prefixed objects and exact legacy paths linked through owner-scoped material_files.';
