-- Correct text concatenation precedence in the job notification key.
create or replace function public.record_job_monitor_run(p_run jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_hash text;
  v_receipt public.operation_receipts%rowtype;
  v_execution_id uuid;
  v_profile_id uuid;
  v_rubric_id uuid;
  v_role jsonb;
  v_company_id uuid;
  v_job_id uuid;
  v_snapshot_id uuid;
  v_assessment_id uuid;
  v_notification_id uuid;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null or jsonb_typeof(p_run) <> 'object'
     or jsonb_typeof(p_run -> 'roles') <> 'array' or jsonb_array_length(p_run -> 'roles') = 0
     or (p_run ->> 'status') not in ('succeeded', 'partial', 'failed') then
    raise exception 'run requires operation_key, status, and at least one role' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(convert_to(p_run::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_job_monitor_run' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_job_monitor_run(p_operation_key);
  end if;
  select id into v_profile_id from public.candidate_profile_versions
    where owner_id = v_owner_id and version_label = p_run ->> 'profile_label';
  select id into v_rubric_id from public.scoring_rubric_versions
    where owner_id = v_owner_id and version_label = p_run ->> 'rubric_label';
  if v_profile_id is null or v_rubric_id is null then
    raise exception 'approved profile and rubric labels are required' using errcode = 'P0002';
  end if;
  insert into public.monitor_executions(owner_id, monitor_type, execution_key, started_at, completed_at, status, scope, summary, failures, scheduler, dependency_note)
  values (v_owner_id, 'job_discovery', p_run ->> 'execution_key', (p_run ->> 'started_at')::timestamptz,
    (p_run ->> 'completed_at')::timestamptz, p_run ->> 'status', coalesce(p_run -> 'scope', '{}'::jsonb),
    coalesce(p_run -> 'summary', '{}'::jsonb), coalesce(p_run -> 'failures', '[]'::jsonb),
    coalesce(nullif(p_run ->> 'scheduler', ''), 'manual'), nullif(p_run ->> 'dependency_note', ''))
  returning id into v_execution_id;
  v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'monitor_execution', 'id', v_execution_id));

  for v_role in select value from jsonb_array_elements(p_run -> 'roles')
  loop
    if nullif(btrim(v_role ->> 'company_name'), '') is null or nullif(btrim(v_role ->> 'title'), '') is null
       or nullif(btrim(v_role ->> 'source_name'), '') is null or nullif(btrim(v_role ->> 'source_identifier'), '') is null
       or coalesce(v_role ->> 'source_url', '') !~ '^https://'
       or coalesce((v_role ->> 'score')::numeric, -1) not between 0 and 100
       or coalesce((v_role ->> 'confidence')::numeric, -1) not between 0 and 1 then
      raise exception 'each role requires company, title, source identity, https URL, score, and confidence' using errcode = '22023';
    end if;
    select id into v_company_id from public.companies
      where owner_id = v_owner_id and normalized_name = lower(btrim(v_role ->> 'company_name')) and archived_at is null;
    if v_company_id is null then raise exception 'company is not registered: %', v_role ->> 'company_name' using errcode = 'P0002'; end if;
    insert into public.job_postings(owner_id, company_id, title, source_url, source_identifier, source_name, status,
      first_seen_at, last_seen_at, incomplete_reason, location, work_arrangement, posted_at, closing_at)
    values (v_owner_id, v_company_id, btrim(v_role ->> 'title'), btrim(v_role ->> 'source_url'),
      btrim(v_role ->> 'source_identifier'), btrim(v_role ->> 'source_name'), coalesce(nullif(v_role ->> 'status', ''), 'open'),
      (v_role ->> 'first_seen_at')::timestamptz, (v_role ->> 'last_seen_at')::timestamptz,
      nullif(v_role ->> 'incomplete_reason', ''), nullif(v_role ->> 'location', ''),
      nullif(v_role ->> 'work_arrangement', ''), nullif(v_role ->> 'posted_at', '')::timestamptz,
      nullif(v_role ->> 'closing_at', '')::timestamptz)
    on conflict (owner_id, source_name, source_identifier) where source_name is not null and source_identifier is not null
    do update set title = excluded.title, source_url = excluded.source_url, status = excluded.status,
      last_seen_at = excluded.last_seen_at, incomplete_reason = excluded.incomplete_reason,
      location = excluded.location, work_arrangement = excluded.work_arrangement,
      posted_at = excluded.posted_at, closing_at = excluded.closing_at,
      updated_at = timezone('utc', now()), lock_version = public.job_postings.lock_version + 1
    returning id into v_job_id;
    insert into public.job_description_snapshots(owner_id, job_posting_id, captured_at, content_text, content_sha256, source_url, unavailable_reason)
    values (v_owner_id, v_job_id, (v_role ->> 'captured_at')::timestamptz, nullif(v_role ->> 'description_summary', ''),
      encode(extensions.digest(convert_to(coalesce(v_role ->> 'description_summary', ''), 'UTF8'), 'sha256'), 'hex'),
      btrim(v_role ->> 'source_url'), nullif(v_role ->> 'unavailable_reason', '')) returning id into v_snapshot_id;
    insert into public.fit_assessments(owner_id, job_posting_id, job_description_snapshot_id, candidate_profile_version_id,
      scoring_rubric_version_id, score, confidence, rationale, strengths, gaps, constraints, assessed_at, provenance)
    values (v_owner_id, v_job_id, v_snapshot_id, v_profile_id, v_rubric_id,
      (v_role ->> 'score')::numeric, (v_role ->> 'confidence')::numeric, nullif(v_role ->> 'rationale', ''),
      coalesce(v_role -> 'strengths', '[]'::jsonb), coalesce(v_role -> 'gaps', '[]'::jsonb),
      coalesce(v_role -> 'constraints', '[]'::jsonb), (v_role ->> 'assessed_at')::timestamptz,
      jsonb_build_object('source_url', v_role ->> 'source_url', 'execution_id', v_execution_id,
        'score_label', 'profile-to-role fit score', 'not_hiring_probability', true))
    returning id into v_assessment_id;
    v_result_ids := v_result_ids || jsonb_build_array(
      jsonb_build_object('type', 'job_posting', 'id', v_job_id),
      jsonb_build_object('type', 'job_description_snapshot', 'id', v_snapshot_id),
      jsonb_build_object('type', 'fit_assessment', 'id', v_assessment_id));
    if coalesce((v_role ->> 'notify')::boolean, false) then
      insert into public.private_notifications(owner_id, notification_key, notification_type, title, body)
      values (v_owner_id, concat('job:', v_role ->> 'source_name', ':', v_role ->> 'source_identifier'), 'job_shortlist',
        btrim(v_role ->> 'title'), jsonb_build_object('job_posting_id', v_job_id, 'assessment_id', v_assessment_id,
          'score', (v_role ->> 'score')::numeric, 'confidence', (v_role ->> 'confidence')::numeric,
          'company_name', btrim(v_role ->> 'company_name')))
      on conflict (owner_id, notification_key) do update set body = excluded.body, title = excluded.title, state = 'unread', created_at = timezone('utc', now())
      returning id into v_notification_id;
      v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'private_notification', 'id', v_notification_id));
    end if;
  end loop;
  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'record_job_monitor_run', v_hash, v_result_ids);
  return public.read_back_job_monitor_run(p_operation_key);
end;
$$;

