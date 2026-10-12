-- Rolled-back synthetic fixtures verify owner-scoped posting deactivation.
begin;
set local statement_timeout = '15s';

create temporary table lifecycle_results (name text, passed boolean);
grant select, insert on lifecycle_results to authenticated;

do $$
declare
  v_owner uuid := '81000000-0000-0000-0000-000000000010';
  v_company uuid := '82000000-0000-0000-0000-000000000010';
  v_job uuid := '83000000-0000-0000-0000-000000000010';
  v_notification uuid := '84000000-0000-0000-0000-000000000010';
  v_seen timestamptz := '2026-10-10T10:00:00Z';
  v_checks jsonb;
  v_first jsonb;
  v_replay jsonb;
begin
  insert into auth.users(id, aud, role) values(v_owner, 'authenticated', 'authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner);
  insert into public.companies(id, owner_id, name) values(v_company, v_owner, 'Synthetic lifecycle company');
  insert into public.job_postings(
    id, owner_id, company_id, title, source_url, source_identifier, source_name,
    status, first_seen_at, last_seen_at
  ) values (
    v_job, v_owner, v_company, 'Synthetic disappearing role',
    'https://example.invalid/jobs/disappearing', 'synthetic-disappearing', 'Synthetic careers',
    'open', v_seen, v_seen
  );
  insert into public.private_notifications(id, owner_id, notification_key, notification_type, title, body)
  values (v_notification, v_owner, 'job:Synthetic careers:synthetic-disappearing', 'job_shortlist',
    'Synthetic disappearing role', jsonb_build_object('job_posting_id', v_job));

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  insert into lifecycle_results values(
    'Open inventory includes the owner posting before reconciliation',
    (public.list_open_job_postings_for_monitor(500) #> '{jobs,0}' ->> 'id')::uuid = v_job
  );

  v_checks := jsonb_build_array(jsonb_build_object(
    'source_name', 'Synthetic careers',
    'source_identifier', 'synthetic-disappearing',
    'source_url', 'https://example.invalid/jobs/disappearing',
    'status', 'unavailable',
    'checked_at', '2026-10-11T10:30:00Z',
    'reason', 'Official detail page returned a verified not-found response.'
  ));
  v_first := public.record_job_posting_status_checks(v_checks, 'synthetic-lifecycle-v1');
  v_replay := public.record_job_posting_status_checks(v_checks, 'synthetic-lifecycle-v1');

  insert into lifecycle_results values
    ('Exact replay returns the same authoritative result', v_first = v_replay),
    ('Readback exposes the inactive posting and evidence',
      v_first #>> '{checks,0,job,status}' = 'unavailable'
      and v_first #>> '{checks,0,evidence,unavailable_reason}' = 'Official detail page returned a verified not-found response.'),
    ('Inactive posting disappears from the open inventory',
      jsonb_array_length(public.list_open_job_postings_for_monitor(500) -> 'jobs') = 0),
    ('Anonymous clients cannot list open postings',
      not has_function_privilege('anon', 'public.list_open_job_postings_for_monitor(integer)'::regprocedure, 'execute')),
    ('Anonymous clients cannot record lifecycle checks',
      not has_function_privilege('anon', 'public.record_job_posting_status_checks(jsonb,text)'::regprocedure, 'execute')),
    ('Authenticated owners retain the reviewed lifecycle operation',
      has_function_privilege('authenticated', 'public.record_job_posting_status_checks(jsonb,text)'::regprocedure, 'execute'));
  execute 'reset role';

  insert into lifecycle_results values
    ('Posting is retained with inactive status and original last-seen time',
      (select status = 'unavailable' and last_seen_at = v_seen from public.job_postings where id = v_job)),
    ('Unread shortlist notification is archived',
      (select state = 'archived' from public.private_notifications where id = v_notification)),
    ('Closure evidence is retained without rewriting prior descriptions',
      (select count(*) = 1 from public.job_description_snapshots where owner_id = v_owner and job_posting_id = v_job and content_text is null)),
    ('Exact replay keeps one operation receipt',
      (select count(*) = 1 from public.operation_receipts where owner_id = v_owner and operation_key = 'synthetic-lifecycle-v1'));
end;
$$;

do $$
begin
  if exists(select 1 from lifecycle_results where passed is distinct from true) then
    raise exception 'job posting lifecycle regression failed';
  end if;
end;
$$;

select name, passed from lifecycle_results order by name;
rollback;
