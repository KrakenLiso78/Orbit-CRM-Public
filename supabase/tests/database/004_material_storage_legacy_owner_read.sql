begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(4);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'orbit_materials_owner_read'
  ),
  'Storage objects expose the reviewed Orbit owner-read policy'
);

select ok(
  (
    select roles = array['authenticated'::name]
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'orbit_materials_owner_read'
  ),
  'the Orbit material read policy applies only to authenticated users'
);

select ok(
  (
    select cmd = 'SELECT'
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'orbit_materials_owner_read'
  ),
  'the Orbit material policy grants read access only'
);

select ok(
  (
    select qual ilike '%material_files%'
       and qual ilike '%auth.uid%'
       and qual ilike '%storage_object_path%'
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'orbit_materials_owner_read'
  ),
  'legacy reads require an exact owner-scoped material_files link'
);

select * from finish();
rollback;
