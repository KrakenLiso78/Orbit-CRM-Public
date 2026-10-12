begin;

-- Acceptance traceability: root SC-017-018; monitor SC-013-014; CRM SC-013-014.

create temporary table promotion_results (check_name text primary key, passed boolean not null);

do $$
declare
  o uuid := '11111111-1111-4111-8111-111111111111';
  other_owner uuid := '22222222-2222-4222-8222-222222222222';
  v_company_id uuid := gen_random_uuid();
  v_job_id uuid := gen_random_uuid();
  v_opportunity_id uuid;
  result jsonb;
  applications_before integer;
begin
  insert into auth.users(id, aud, role, email) values
    (o, 'authenticated', 'authenticated', 'promotion-owner@example.invalid'),
    (other_owner, 'authenticated', 'authenticated', 'promotion-other@example.invalid');
  insert into public.crm_owner_profiles(owner_id) values (o), (other_owner);
  insert into public.companies(id, owner_id, name) values (v_company_id, o, 'Synthetic Pharma');
  insert into public.job_postings(
    id, owner_id, company_id, title, source_url, source_identifier, source_name,
    status, first_seen_at, last_seen_at, location, work_arrangement
  ) values (
    v_job_id, o, v_company_id, 'Synthetic AI Product Lead',
    'https://careers.example.invalid/jobs/synthetic-ai-product-lead', 'synthetic-001',
    'Synthetic Careers', 'open', now() - interval '1 day', now(), 'Madrid', 'hybrid'
  );

  select count(*) into applications_before from public.applications where owner_id = o;
  perform set_config('request.jwt.claim.sub', o::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  result := public.promote_job_posting_to_opportunity(v_job_id, 'promotion-test-001');
  v_opportunity_id := (result #>> '{opportunity,id}')::uuid;

  insert into promotion_results values
    ('Promotion reports a saved non-application decision', result ->> 'saved' = 'true' and result ->> 'application_created' = 'false'),
    ('Opportunity is linked to the monitored posting', (select opportunity_id = v_opportunity_id from public.job_postings where id = v_job_id)),
    ('Opportunity copies the role and active state', (select title = 'Synthetic AI Product Lead' and status = 'Open' and source_type = 'job_monitor' and work_mode = 'Hibrido' from public.opportunities where id = v_opportunity_id)),
    ('No application is inferred', (select count(*) from public.applications where owner_id = o) = applications_before),
    ('Exact replay returns the same opportunity', (public.promote_job_posting_to_opportunity(v_job_id, 'promotion-test-001') #>> '{opportunity,id}')::uuid = v_opportunity_id);

  result := public.promote_job_posting_to_opportunity(v_job_id, 'promotion-test-002');
  insert into promotion_results values
    ('A new key reuses the existing linked opportunity', (result #>> '{opportunity,id}')::uuid = v_opportunity_id and (select count(*) from public.opportunities where owner_id = o and company_id = v_company_id and title = 'Synthetic AI Product Lead') = 1),
    ('Authoritative readback returns official URL', public.read_back_job_posting_promotion('promotion-test-001') #>> '{job_posting,source_url}' = 'https://careers.example.invalid/jobs/synthetic-ai-product-lead');

  begin
    perform public.promote_job_posting_to_opportunity(gen_random_uuid(), 'promotion-test-001');
    raise exception 'changed replay accepted';
  exception when unique_violation then
    insert into promotion_results values ('Changed replay is denied', true);
  end;

  begin
    perform public.promote_job_posting_to_opportunity(gen_random_uuid(), 'promotion-unknown');
    raise exception 'unknown posting accepted';
  exception when no_data_found then
    insert into promotion_results values ('Unknown posting is denied', true);
  end;

  perform set_config('request.jwt.claim.sub', other_owner::text, true);
  begin
    perform public.promote_job_posting_to_opportunity(v_job_id, 'promotion-foreign');
    raise exception 'foreign owner write accepted';
  exception when no_data_found then
    insert into promotion_results values ('Wrong owner write is denied', true);
  end;

  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.promote_job_posting_to_opportunity(v_job_id, 'promotion-expired');
    raise exception 'missing identity accepted';
  exception when insufficient_privilege then
    insert into promotion_results values ('Missing or expired identity is denied', true);
  end;

  insert into promotion_results values
    ('Anonymous execution is denied', not has_function_privilege('anon', 'public.promote_job_posting_to_opportunity(uuid,text)'::regprocedure, 'execute')),
    ('Authenticated execution is explicit', has_function_privilege('authenticated', 'public.promote_job_posting_to_opportunity(uuid,text)'::regprocedure, 'execute'));
end;
$$;

select * from promotion_results order by check_name;

do $$ begin
  if exists (select 1 from promotion_results where not passed) then
    raise exception 'job posting promotion regression failed';
  end if;
end $$;

rollback;
