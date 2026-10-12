begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;

select plan(70);

select has_function('public', 'resolve_company', array['text', 'text', 'text', 'integer'], 'company resolution RPC exists');
select has_function('public', 'create_independent_company', array['jsonb', 'text'], 'independent company creation RPC exists');
select has_function('public', 'read_back_independent_company', array['text'], 'independent company readback RPC exists');
select has_function('public', 'resolve_contact', array['text', 'text', 'text', 'integer'], 'contact resolution RPC exists');
select has_function('public', 'create_independent_contact', array['jsonb', 'text'], 'independent contact creation RPC exists');
select has_function('public', 'read_back_independent_contact', array['text'], 'independent contact readback RPC exists');
select has_function('public', 'capture_call_report_with_entities', array['jsonb', 'text'], 'atomic Call Report entity capture RPC exists');
select has_function('public', 'prepare_interaction_capture', array['jsonb'], 'capture preparation RPC exists');
select has_function('public', 'record_interaction_capture', array['jsonb', 'text'], 'atomic interaction capture RPC exists');
select has_function('public', 'read_back_interaction_capture', array['text'], 'capture readback RPC exists');
select has_function('public', 'correct_call_report_record', array['text', 'uuid', 'bigint', 'jsonb', 'text', 'jsonb', 'text'], 'record correction RPC exists');
select has_function('public', 'read_back_call_report_correction', array['text'], 'correction readback RPC exists');
select has_function('public', 'complete_task', array['uuid', 'timestamp with time zone', 'text', 'text'], 'task completion RPC exists');
select has_function('public', 'read_back_task_completion', array['text'], 'task completion readback RPC exists');
select has_function('public', 'prepare_application_capture', array['jsonb'], 'application capture preparation RPC exists');
select has_function('public', 'record_application_capture', array['jsonb', 'text'], 'atomic application capture RPC exists');
select has_function('public', 'read_back_application_capture', array['text'], 'application capture readback RPC exists');

select ok(not has_function_privilege('anon', 'public.resolve_company(text, text, text, integer)'::regprocedure, 'execute'), 'anonymous clients cannot resolve companies');
select ok(not has_function_privilege('anon', 'public.create_independent_company(jsonb, text)'::regprocedure, 'execute'), 'anonymous clients cannot create independent companies');
select ok(not has_function_privilege('anon', 'public.create_independent_contact(jsonb, text)'::regprocedure, 'execute'), 'anonymous clients cannot create independent contacts');
select ok(not has_function_privilege('anon', 'public.record_interaction_capture(jsonb, text)'::regprocedure, 'execute'), 'anonymous clients cannot capture interactions');
select ok(not has_function_privilege('anon', 'public.capture_call_report_with_entities(jsonb, text)'::regprocedure, 'execute'), 'anonymous clients cannot capture entities');
select ok(not has_function_privilege('anon', 'public.complete_task(uuid, timestamptz, text, text)'::regprocedure, 'execute'), 'anonymous clients cannot complete tasks');
select ok(not has_function_privilege('anon', 'public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text)'::regprocedure, 'execute'), 'anonymous clients cannot correct records');
select ok(not has_function_privilege('anon', 'public.record_application_capture(jsonb, text)'::regprocedure, 'execute'), 'anonymous clients cannot capture applications');
select ok(
  case when to_regprocedure('public.rls_auto_enable()') is null then true
  else not has_function_privilege('authenticated', to_regprocedure('public.rls_auto_enable()'), 'execute') end,
  'Optional RLS event trigger is absent or not a callable authenticated RPC'
);

select ok(has_function_privilege('authenticated', 'public.resolve_company(text, text, text, integer)'::regprocedure, 'execute'), 'authenticated owners can resolve companies');
select ok(has_function_privilege('authenticated', 'public.create_independent_company(jsonb, text)'::regprocedure, 'execute'), 'authenticated owners can create independent companies');
select ok(has_function_privilege('authenticated', 'public.create_independent_contact(jsonb, text)'::regprocedure, 'execute'), 'authenticated owners can create independent contacts');
select ok(has_function_privilege('authenticated', 'public.prepare_interaction_capture(jsonb)'::regprocedure, 'execute'), 'authenticated owners can prepare captures');
select ok(has_function_privilege('authenticated', 'public.record_interaction_capture(jsonb, text)'::regprocedure, 'execute'), 'authenticated owners can capture interactions');
select ok(has_function_privilege('authenticated', 'public.capture_call_report_with_entities(jsonb, text)'::regprocedure, 'execute'), 'authenticated owners can capture entities');
select ok(has_function_privilege('authenticated', 'public.read_back_interaction_capture(text)'::regprocedure, 'execute'), 'authenticated owners can read captures back');
select ok(has_function_privilege('authenticated', 'public.complete_task(uuid, timestamptz, text, text)'::regprocedure, 'execute'), 'authenticated owners can complete commitments');
select ok(has_function_privilege('authenticated', 'public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text)'::regprocedure, 'execute'), 'authenticated owners can correct records');
select ok(has_function_privilege('authenticated', 'public.read_back_call_report_correction(text)'::regprocedure, 'execute'), 'authenticated owners can read corrections back');
select ok(has_function_privilege('authenticated', 'public.prepare_application_capture(jsonb)'::regprocedure, 'execute'), 'authenticated owners can prepare application captures');
select ok(has_function_privilege('authenticated', 'public.record_application_capture(jsonb, text)'::regprocedure, 'execute'), 'authenticated owners can capture applications');
select ok(has_function_privilege('authenticated', 'public.read_back_application_capture(text)'::regprocedure, 'execute'), 'authenticated owners can read application captures back');
select ok(not has_function_privilege('service_role', 'public.record_interaction_capture(jsonb, text)'::regprocedure, 'execute'), 'service role has no Call Report RPC execute grant');
select ok(not has_function_privilege('service_role', 'public.record_application_capture(jsonb, text)'::regprocedure, 'execute'), 'service role has no application capture RPC execute grant');

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at
)
values (
  '00000000-0000-0000-0000-000000000000',
  '30000000-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'call-report-correction-owner@example.invalid',
  '',
  now(),
  now(),
  now()
);

insert into public.crm_owner_profiles (owner_id)
values ('30000000-0000-0000-0000-000000000001');

insert into public.companies (id, owner_id, name, notes)
values (
  '31000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  'Synthetic Correction Co',
  'before correction'
);

insert into public.opportunities (id, owner_id, company_id, title, status)
values (
  '32000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  'Synthetic Application Role',
  'Open'
);

insert into public.job_postings (
  id, owner_id, company_id, opportunity_id, title, source_identifier, status, first_seen_at
) values (
  '33000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  '31000000-0000-0000-0000-000000000001',
  '32000000-0000-0000-0000-000000000001',
  'Synthetic Application Role',
  'SYN-001',
  'open',
  now()
);

select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

set local role authenticated;

select lives_ok($sql$
  select public.correct_call_report_record(
    'company',
    '31000000-0000-0000-0000-000000000001'::uuid,
    1,
    '{"notes":"after correction"}'::jsonb,
    'Synthetic correction test',
    '{"source_system":"test","source_database":"pgtap","source_record_id":"correction-digest"}'::jsonb,
    'call-report-correction-digest-test'
  )
$sql$, 'authenticated owner can execute a valid correction');

select throws_ok($sql$
  select public.correct_call_report_record(
    'company',
    '31000000-0000-0000-0000-000000000001'::uuid,
    1,
    '{"notes":"stale correction"}'::jsonb,
    'Synthetic stale version test',
    '{"source_system":"test","source_database":"pgtap","source_record_id":"stale-correction"}'::jsonb,
    'call-report-stale-correction-test'
  )
$sql$, 'PT409', 'record changed since it was read; resolve it again before correcting',
  'stale correction returns a non-retryable HTTP conflict');

reset role;

select is(
  (select notes from public.companies where id = '31000000-0000-0000-0000-000000000001'),
  'after correction',
  'valid correction applies the authorized change'
);

select ok(
  exists (
    select 1
    from public.operation_receipts
    where owner_id = '30000000-0000-0000-0000-000000000001'
      and operation_key = 'call-report-correction-digest-test'
      and operation_type = 'correct_call_report_record'
      and request_sha256 ~ '^[0-9a-f]{64}$'
  ),
  'valid correction records an operation receipt'
);

select ok(
  exists (
    select 1
    from public.crm_corrections
    where owner_id = '30000000-0000-0000-0000-000000000001'
      and operation_key = 'call-report-correction-digest-test'
      and before_data ->> 'notes' = 'before correction'
      and after_data ->> 'notes' = 'after correction'
  ),
  'valid correction preserves before and after history'
);

select is(
  public.read_back_call_report_correction('call-report-correction-digest-test') -> 'record' ->> 'notes',
  'after correction',
  'correction readback returns the updated record'
);

set local role authenticated;

select lives_ok($sql$
  select public.correct_call_report_record(
    'company',
    '31000000-0000-0000-0000-000000000001'::uuid,
    1,
    '{"notes":"after correction"}'::jsonb,
    'Synthetic correction test',
    '{"source_system":"test","source_database":"pgtap","source_record_id":"correction-digest"}'::jsonb,
    'call-report-correction-digest-test'
  )
$sql$, 'same correction request can be replayed idempotently');

reset role;

select is(
  (select count(*)::integer from public.crm_corrections where operation_key = 'call-report-correction-digest-test'),
  1,
  'idempotent replay does not create another correction history row'
);

set local role authenticated;

select lives_ok($sql$
  select public.prepare_application_capture(
    jsonb_build_object(
      'application', jsonb_build_object(
        'company_id', '31000000-0000-0000-0000-000000000001',
        'opportunity_id', '32000000-0000-0000-0000-000000000001',
        'job_posting_id', '33000000-0000-0000-0000-000000000001',
        'submitted_at', '2026-09-17T10:00:00Z',
        'channel', 'Workday',
        'source_identifier', 'SYN-001',
        'submission_evidence', 'Synthetic submitted application.',
        'missing_snapshot_reason', 'Synthetic posting has no snapshot.'
      ),
      'materials', jsonb_build_array(
        jsonb_build_object(
          'name', 'Synthetic job description PDF',
          'material_type', 'Job description PDF',
          'version_label', 'Captured 2026-09-17',
          'storage_object_path', '30000000-0000-0000-0000-000000000001/applications/synthetic-job-description.pdf',
          'original_filename', 'synthetic-job-description.pdf',
          'media_type', 'application/pdf',
          'byte_size', 1234,
          'sha256', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'purpose', 'job_description_snapshot'
        )
      )
    )
  )
$sql$, 'authenticated owner can prepare an application capture');

select lives_ok($sql$
  select public.record_application_capture(
    jsonb_build_object(
      'application', jsonb_build_object(
        'company_id', '31000000-0000-0000-0000-000000000001',
        'opportunity_id', '32000000-0000-0000-0000-000000000001',
        'job_posting_id', '33000000-0000-0000-0000-000000000001',
        'submitted_at', '2026-09-17T10:00:00Z',
        'channel', 'Workday',
        'source_identifier', 'SYN-001',
        'submission_evidence', 'Synthetic submitted application.',
        'missing_snapshot_reason', 'Synthetic posting has no snapshot.'
      ),
      'materials', jsonb_build_array(
        jsonb_build_object(
          'name', 'Synthetic job description PDF',
          'material_type', 'Job description PDF',
          'version_label', 'Captured 2026-09-17',
          'storage_object_path', '30000000-0000-0000-0000-000000000001/applications/synthetic-job-description.pdf',
          'original_filename', 'synthetic-job-description.pdf',
          'media_type', 'application/pdf',
          'byte_size', 1234,
          'sha256', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'purpose', 'job_description_snapshot'
        )
      )
    ),
    'application-capture-test'
  )
$sql$, 'authenticated owner can record an application capture with PDF metadata');

select is(
  (select count(*)::integer from public.applications where source_identifier = 'SYN-001'),
  1,
  'application capture creates one application'
);

select is(
  (select count(*)::integer from public.application_events where operation_key = 'application-capture-test:submitted'),
  1,
  'application capture records one submitted event'
);

select is(
  (
    select count(*)::integer
    from public.application_material_versions link
    join public.applications application
      on application.owner_id = link.owner_id
     and application.id = link.application_id
    where application.source_identifier = 'SYN-001'
      and link.purpose = 'job_description_snapshot'
  ),
  1,
  'application capture links job description material to application'
);

select is(
  (
    select file.sha256
    from public.material_files file
    join public.material_versions version
      on version.owner_id = file.owner_id
     and version.id = file.material_version_id
    join public.materials material
      on material.owner_id = version.owner_id
     and material.id = version.material_id
    where material.name = 'Synthetic job description PDF'
  ),
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'application capture registers PDF file metadata'
);

select is(
  public.read_back_application_capture('application-capture-test') -> 'current_state' ->> 'current_state',
  'submitted',
  'application capture readback returns current submitted state'
);

select is(
  jsonb_array_length(public.read_back_application_capture('application-capture-test') -> 'materials'),
  1,
  'application capture readback returns linked material'
);

select lives_ok($sql$
  select public.record_application_capture(
    jsonb_build_object(
      'application', jsonb_build_object(
        'company_id', '31000000-0000-0000-0000-000000000001',
        'opportunity_id', '32000000-0000-0000-0000-000000000001',
        'job_posting_id', '33000000-0000-0000-0000-000000000001',
        'submitted_at', '2026-09-17T10:00:00Z',
        'channel', 'Workday',
        'source_identifier', 'SYN-001',
        'submission_evidence', 'Synthetic submitted application.',
        'missing_snapshot_reason', 'Synthetic posting has no snapshot.'
      ),
      'materials', jsonb_build_array(
        jsonb_build_object(
          'name', 'Synthetic job description PDF',
          'material_type', 'Job description PDF',
          'version_label', 'Captured 2026-09-17',
          'storage_object_path', '30000000-0000-0000-0000-000000000001/applications/synthetic-job-description.pdf',
          'original_filename', 'synthetic-job-description.pdf',
          'media_type', 'application/pdf',
          'byte_size', 1234,
          'sha256', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'purpose', 'job_description_snapshot'
        )
      )
    ),
    'application-capture-test'
  )
$sql$, 'same application capture request can be replayed idempotently');

select is(
  (select count(*)::integer from public.operation_receipts where operation_key = 'application-capture-test'),
  1,
  'application capture replay does not create another receipt'
);

select is(
  (select count(*)::integer from public.application_material_versions link join public.applications application on application.owner_id = link.owner_id and application.id = link.application_id where application.source_identifier = 'SYN-001'),
  1,
  'application capture replay does not duplicate material link'
);

select lives_ok($sql$
  select public.create_independent_contact(
    jsonb_build_object(
      'name', 'Synthetic Independent Contact',
      'email', 'synthetic-independent@example.invalid',
      'linkedin_url', 'https://www.linkedin.com/in/synthetic-independent',
      'source_channel', 'Synthetic test',
      'source', jsonb_build_object(
        'source_system', 'test',
        'source_database', 'pgtap',
        'source_record_id', 'independent-contact-source'
      )
    ),
    'independent-contact-test'
  )
$sql$, 'authenticated owner can create an independent contact');

select is(
  public.read_back_independent_contact('independent-contact-test') -> 'contact' ->> 'name',
  'Synthetic Independent Contact',
  'independent contact readback returns the saved contact'
);

select is(
  (
    select count(*)::integer
    from public.contact_company_affiliations relation
    join public.contacts contact on contact.owner_id = relation.owner_id and contact.id = relation.contact_id
    where contact.email = 'synthetic-independent@example.invalid'
  ),
  0,
  'independent contact creation does not create an affiliation'
);

select lives_ok($sql$
  select public.create_independent_contact(
    jsonb_build_object(
      'name', 'Synthetic Independent Contact',
      'email', 'synthetic-independent@example.invalid',
      'linkedin_url', 'https://www.linkedin.com/in/synthetic-independent',
      'source_channel', 'Synthetic test',
      'source', jsonb_build_object(
        'source_system', 'test',
        'source_database', 'pgtap',
        'source_record_id', 'independent-contact-source'
      )
    ),
    'independent-contact-test'
  )
$sql$, 'same independent contact request can be replayed idempotently');

select is(
  (select count(*)::integer from public.operation_receipts where operation_key = 'independent-contact-test'),
  1,
  'independent contact replay does not create another receipt'
);

select lives_ok($sql$
  select public.create_independent_company(
    jsonb_build_object(
      'name', 'Synthetic Independent Company',
      'website_url', 'https://synthetic-independent.example.invalid',
      'linkedin_url', 'https://www.linkedin.com/company/synthetic-independent',
      'priority', 'Target A',
      'source', jsonb_build_object(
        'source_system', 'test',
        'source_database', 'pgtap',
        'source_record_id', 'independent-company-source'
      )
    ),
    'independent-company-test'
  )
$sql$, 'authenticated owner can create an independent company');

select is(
  public.read_back_independent_company('independent-company-test') -> 'company' ->> 'name',
  'Synthetic Independent Company',
  'independent company readback returns the saved company'
);

select is(
  (
    select count(*)::integer
    from public.contact_company_affiliations relation
    join public.companies company on company.owner_id = relation.owner_id and company.id = relation.company_id
    where company.name = 'Synthetic Independent Company'
  ),
  0,
  'independent company creation does not create an affiliation'
);

select lives_ok($sql$
  select public.create_independent_company(
    jsonb_build_object(
      'name', 'Synthetic Independent Company',
      'website_url', 'https://synthetic-independent.example.invalid',
      'linkedin_url', 'https://www.linkedin.com/company/synthetic-independent',
      'priority', 'Target A',
      'source', jsonb_build_object(
        'source_system', 'test',
        'source_database', 'pgtap',
        'source_record_id', 'independent-company-source'
      )
    ),
    'independent-company-test'
  )
$sql$, 'same independent company request can be replayed idempotently');

select is(
  (select count(*)::integer from public.operation_receipts where operation_key = 'independent-company-test'),
  1,
  'independent company replay does not create another receipt'
);

reset role;

select * from finish();
rollback;
