begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(33);

create or replace function pg_temp.raises(statement text)
returns boolean
language plpgsql
as $$
begin
  execute statement;
  return false;
exception when others then
  return true;
end;
$$;

select has_table('public', 'companies', 'companies table exists');
select has_table('public', 'contact_company_affiliations', 'contact/company bridge exists');
select has_table('public', 'opportunity_material_versions', 'opportunity/material bridge exists');
select has_table('public', 'source_records', 'source crosswalk exists');

select ok(
  not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and c.relname = any (array[
        'crm_owner_profiles', 'companies', 'contacts', 'contact_company_affiliations',
        'opportunities', 'opportunity_contacts', 'job_postings',
        'job_description_snapshots', 'materials', 'material_versions',
        'material_files', 'opportunity_material_versions', 'candidate_profile_versions',
        'scoring_rubric_versions', 'fit_assessments', 'applications',
        'application_material_versions', 'application_events', 'interactions',
        'interaction_contacts', 'tasks', 'task_contacts', 'task_events',
        'market_signals', 'operation_receipts', 'source_records'
      ])
      and (not c.relrowsecurity or not c.relforcerowsecurity)
  ),
  'every private CRM table has forced RLS'
);

select ok(
  not exists (
    select 1
    from pg_constraint c
    join pg_class source_table on source_table.oid = c.conrelid
    join pg_namespace source_schema on source_schema.oid = source_table.relnamespace
    join pg_class target_table on target_table.oid = c.confrelid
    join pg_namespace target_schema on target_schema.oid = target_table.relnamespace
    where c.contype = 'f'
      and source_schema.nspname = 'public'
      and target_schema.nspname = 'public'
      and (
        not exists (
          select 1
          from unnest(c.conkey) source_key(attnum)
          join pg_attribute source_attribute
            on source_attribute.attrelid = c.conrelid
           and source_attribute.attnum = source_key.attnum
          where source_attribute.attname = 'owner_id'
        )
        or not exists (
          select 1
          from unnest(c.confkey) target_key(attnum)
          join pg_attribute target_attribute
            on target_attribute.attrelid = c.confrelid
           and target_attribute.attnum = target_key.attnum
          where target_attribute.attname = 'owner_id'
        )
      )
  ),
  'every CRM-to-CRM foreign key is owner scoped on both sides'
);

select hasnt_column('public', 'companies', 'opportunity_ids', 'company does not duplicate inverse opportunity links');
select hasnt_column('public', 'contacts', 'company_id', 'contact/company history uses one affiliation bridge');
select hasnt_column('public', 'opportunities', 'material_ids', 'opportunity/material links use one bridge');
select hasnt_column('public', 'applications', 'state', 'application state is derived from immutable events');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'owner-a@example.invalid', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'owner-b@example.invalid', '', now(), now(), now());

insert into public.crm_owner_profiles (owner_id)
values
  ('10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002');

insert into public.companies (id, owner_id, name)
values
  ('11000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Acme'),
  ('11000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Other Co'),
  ('21000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'Acme');

insert into public.contacts (id, owner_id, name)
values
  ('12000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Contact A'),
  ('22000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', 'Contact B');

insert into public.opportunities (id, owner_id, company_id, title)
values (
  '13000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000001',
  'Opportunity A'
);

insert into public.materials (id, owner_id, name)
values
  ('14000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'CV'),
  ('14000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Job description');

insert into public.material_versions (id, owner_id, material_id, version_label)
values
  ('15000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '14000000-0000-0000-0000-000000000001', 'v1'),
  ('15000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '14000000-0000-0000-0000-000000000002', 'captured');

select ok(
  pg_temp.raises($sql$
    insert into public.contact_company_affiliations (owner_id, contact_id, company_id)
    values ('10000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001', '21000000-0000-0000-0000-000000000001')
  $sql$),
  'cross-owner contact/company link is rejected'
);

select lives_ok($sql$
  insert into public.contact_company_affiliations (owner_id, contact_id, company_id)
  values ('10000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001')
$sql$, 'valid contact/company link is accepted');

select ok(
  pg_temp.raises($sql$
    insert into public.contact_company_affiliations (owner_id, contact_id, company_id)
    values ('10000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001', '11000000-0000-0000-0000-000000000001')
  $sql$),
  'duplicate contact/company link is rejected'
);

select ok(
  pg_temp.raises($sql$
    insert into public.companies (owner_id, name)
    values ('10000000-0000-0000-0000-000000000001', '  ACME  ')
  $sql$),
  'normalized duplicate company name is rejected for one owner'
);

select lives_ok($sql$
  insert into public.opportunity_material_versions (owner_id, opportunity_id, material_version_id)
  values
    ('10000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000001', '15000000-0000-0000-0000-000000000001'),
    ('10000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000001', '15000000-0000-0000-0000-000000000002')
$sql$, 'one opportunity accepts multiple distinct material versions');

select ok(
  pg_temp.raises($sql$
    insert into public.opportunity_material_versions (owner_id, opportunity_id, material_version_id)
    values ('10000000-0000-0000-0000-000000000001', '13000000-0000-0000-0000-000000000001', '15000000-0000-0000-0000-000000000001')
  $sql$),
  'duplicate opportunity/material link is rejected'
);

select ok(
  pg_temp.raises($sql$
    insert into public.applications (
      owner_id, company_id, opportunity_id, submitted_at, channel, source_identifier
    ) values (
      '10000000-0000-0000-0000-000000000001',
      '11000000-0000-0000-0000-000000000002',
      '13000000-0000-0000-0000-000000000001',
      now(), 'direct', 'mismatch-test'
    )
  $sql$),
  'application cannot cross-link an opportunity to another company'
);

insert into public.applications (
  id, owner_id, company_id, opportunity_id, submitted_at, channel, submission_evidence
) values (
  '17000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000001',
  '13000000-0000-0000-0000-000000000001',
  now(), 'direct', 'Synthetic acceptance evidence'
);

insert into public.application_material_versions (
  owner_id, application_id, material_version_id
) values (
  '10000000-0000-0000-0000-000000000001',
  '17000000-0000-0000-0000-000000000001',
  '15000000-0000-0000-0000-000000000001'
);

select ok(
  pg_temp.raises($sql$
    update public.material_versions
       set notes = 'Rewritten after submission'
     where id = '15000000-0000-0000-0000-000000000001'
  $sql$),
  'material version used as application evidence cannot be rewritten'
);

insert into public.application_events (
  id, owner_id, application_id, event_type, occurred_at, operation_key
) values (
  '18000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  '17000000-0000-0000-0000-000000000001',
  'submitted', now(), 'application-event-1'
);

select ok(
  pg_temp.raises($sql$
    update public.application_events
       set event_type = 'rejected'
     where id = '18000000-0000-0000-0000-000000000001'
  $sql$),
  'application history is append-only'
);

select ok(
  pg_temp.raises($sql$
    insert into public.interactions (
      owner_id, title, occurred_at, context_company_id, context_application_id
    ) values (
      '10000000-0000-0000-0000-000000000001', 'Bad context', now(),
      '11000000-0000-0000-0000-000000000001',
      '17000000-0000-0000-0000-000000000001'
    )
  $sql$),
  'interaction cannot combine an application with a company context'
);

select lives_ok($sql$
  insert into public.interactions (
    owner_id, title, occurred_at, context_company_id, context_opportunity_id
  ) values (
    '10000000-0000-0000-0000-000000000001', 'Combined synthetic context', now(),
    '11000000-0000-0000-0000-000000000001',
    '13000000-0000-0000-0000-000000000001'
  )
$sql$, 'interaction retains the supported company and opportunity context');

select lives_ok($sql$
  insert into public.interactions (id, owner_id, title, occurred_at)
  values
    ('16000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Same title', now()),
    ('16000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Same title', now())
$sql$, 'interaction titles are not treated as entity identity');

select ok(
  pg_temp.raises($sql$
    insert into public.interaction_contacts (owner_id, interaction_id, contact_id)
    values ('10000000-0000-0000-0000-000000000001', '16000000-0000-0000-0000-000000000001', '22000000-0000-0000-0000-000000000001')
  $sql$),
  'cross-owner interaction/contact link is rejected'
);

select lives_ok($sql$
  insert into public.source_records (
    owner_id, source_system, source_database, source_record_id, company_id
  ) values (
    '10000000-0000-0000-0000-000000000001', 'notion', 'companies', 'roche-page-1',
    '11000000-0000-0000-0000-000000000001'
  )
$sql$, 'one source record maps to one authoritative target');

select lives_ok($sql$
  insert into public.source_records (
    owner_id, source_system, source_database, source_record_id, company_id
  ) values (
    '10000000-0000-0000-0000-000000000001', 'notion', 'companies', 'roche-page-2',
    '11000000-0000-0000-0000-000000000001'
  )
$sql$, 'multiple source duplicates can map to one canonical company');

select ok(
  pg_temp.raises($sql$
    insert into public.source_records (
      owner_id, source_system, source_database, source_record_id, company_id, contact_id
    ) values (
      '10000000-0000-0000-0000-000000000001', 'notion', 'bad', 'bad-map',
      '11000000-0000-0000-0000-000000000001',
      '12000000-0000-0000-0000-000000000001'
    )
  $sql$),
  'source record cannot map to two entity types'
);

select ok(
  pg_temp.raises($sql$
    insert into public.source_records (
      owner_id, source_system, source_database, source_record_id, company_id
    ) values (
      '10000000-0000-0000-0000-000000000001', 'notion', 'companies', 'roche-page-1',
      '11000000-0000-0000-0000-000000000001'
    )
  $sql$),
  'same source record cannot be imported twice'
);

select lives_ok($sql$
  insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256)
  values (
    '10000000-0000-0000-0000-000000000001', 'capture-1', 'record_interaction',
    repeat('a', 64)
  )
$sql$, 'first idempotent operation receipt is accepted');

select ok(
  pg_temp.raises($sql$
    insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256)
    values (
      '10000000-0000-0000-0000-000000000001', 'capture-1', 'record_interaction',
      repeat('a', 64)
    )
  $sql$),
  'duplicate operation key is rejected'
);

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'anon'
      and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
      and table_name in ('companies', 'contacts', 'opportunities', 'applications', 'materials')
  ),
  'anonymous role has no CRM table privileges'
);

select ok(
  not exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and grantee = 'authenticated'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
      and table_name in ('companies', 'contacts', 'opportunities', 'applications', 'materials')
  ),
  'authenticated clients have no direct write privileges'
);

select is(
  (select public from storage.buckets where id = 'orbit-materials'),
  false,
  'material bucket is private'
);

select is(
  (
    select (c.reloptions @> array['security_invoker=true'])
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'current_application_states'
  ),
  true,
  'application state view uses invoker security'
);

select * from finish();
rollback;
