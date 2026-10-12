-- Owner-scoped reassessment reuses retained vacancy evidence and never creates a duplicate description snapshot.

create function public.read_back_job_reassessment_run(p_operation_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
begin
  select * into v_receipt
  from public.operation_receipts
  where owner_id = v_owner_id
    and operation_key = p_operation_key
    and operation_type = 'record_job_reassessment_run';
  if not found then
    raise exception 'job reassessment receipt was not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'saved', true,
    'receipt', to_jsonb(v_receipt) - 'owner_id',
    'execution', (
      select to_jsonb(e) - 'owner_id'
      from public.monitor_executions e
      where e.owner_id = v_owner_id
        and e.id = ((
          select x ->> 'id'
          from jsonb_array_elements(v_receipt.result_record_ids) x
          where x ->> 'type' = 'monitor_execution'
          limit 1
        ))::uuid
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'job', to_jsonb(j) - 'owner_id',
        'assessment', to_jsonb(a) - 'owner_id',
        'profile_label', p.version_label,
        'rubric_label', r.version_label,
        'company_name', c.name
      ) order by a.score desc nulls last, c.name, j.title)
      from public.fit_assessments a
      join public.job_postings j on j.owner_id = a.owner_id and j.id = a.job_posting_id
      join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
      join public.candidate_profile_versions p on p.owner_id = a.owner_id and p.id = a.candidate_profile_version_id
      join public.scoring_rubric_versions r on r.owner_id = a.owner_id and r.id = a.scoring_rubric_version_id
      where a.owner_id = v_owner_id
        and a.id in (
          select (x ->> 'id')::uuid
          from jsonb_array_elements(v_receipt.result_record_ids) x
          where x ->> 'type' = 'fit_assessment'
        )
    ), '[]'::jsonb)
  );
end;
$$;

create function public.record_job_reassessment_run(p_run jsonb, p_operation_key text)
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
  v_job_id uuid;
  v_snapshot_id uuid;
  v_assessment_id uuid;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null
     or jsonb_typeof(p_run) <> 'object'
     or jsonb_typeof(p_run -> 'roles') <> 'array'
     or jsonb_array_length(p_run -> 'roles') = 0
     or (p_run ->> 'status') not in ('succeeded', 'partial', 'failed') then
    raise exception 'reassessment run requires operation_key, status, and at least one role' using errcode = '22023';
  end if;

  v_hash := encode(extensions.digest(convert_to(p_run::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt
  from public.operation_receipts
  where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_job_reassessment_run' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_job_reassessment_run(p_operation_key);
  end if;

  select id into v_profile_id
  from public.candidate_profile_versions
  where owner_id = v_owner_id and version_label = p_run ->> 'profile_label';
  select id into v_rubric_id
  from public.scoring_rubric_versions
  where owner_id = v_owner_id and version_label = p_run ->> 'rubric_label';
  if v_profile_id is null or v_rubric_id is null then
    raise exception 'approved profile and rubric labels are required' using errcode = 'P0002';
  end if;

  insert into public.monitor_executions(
    owner_id, monitor_type, execution_key, started_at, completed_at, status,
    scope, summary, failures, scheduler, dependency_note
  ) values (
    v_owner_id, 'job_discovery', p_run ->> 'execution_key',
    (p_run ->> 'started_at')::timestamptz, (p_run ->> 'completed_at')::timestamptz,
    p_run ->> 'status', coalesce(p_run -> 'scope', '{}'::jsonb),
    coalesce(p_run -> 'summary', '{}'::jsonb), coalesce(p_run -> 'failures', '[]'::jsonb),
    coalesce(nullif(p_run ->> 'scheduler', ''), 'manual'), nullif(p_run ->> 'dependency_note', '')
  ) returning id into v_execution_id;
  v_result_ids := jsonb_build_array(jsonb_build_object('type', 'monitor_execution', 'id', v_execution_id));

  for v_role in select value from jsonb_array_elements(p_run -> 'roles')
  loop
    if nullif(v_role ->> 'job_posting_id', '') is null
       or nullif(v_role ->> 'job_description_snapshot_id', '') is null
       or coalesce((v_role ->> 'score')::numeric, -1) not between 0 and 100
       or coalesce((v_role ->> 'confidence')::numeric, -1) not between 0 and 1
       or nullif(v_role ->> 'assessed_at', '') is null then
      raise exception 'each reassessment requires posting, snapshot, score, confidence, and assessed_at' using errcode = '22023';
    end if;

    v_job_id := (v_role ->> 'job_posting_id')::uuid;
    v_snapshot_id := (v_role ->> 'job_description_snapshot_id')::uuid;
    perform 1
    from public.job_postings j
    join public.job_description_snapshots s
      on s.owner_id = j.owner_id and s.job_posting_id = j.id
    where j.owner_id = v_owner_id and j.id = v_job_id and j.status = 'open'
      and s.id = v_snapshot_id
      and not exists (
        select 1 from public.job_dismissals d
        where d.owner_id = j.owner_id and d.job_posting_id = j.id
      );
    if not found then
      raise exception 'open non-dismissed posting and retained snapshot are required' using errcode = 'P0002';
    end if;

    insert into public.fit_assessments(
      owner_id, job_posting_id, job_description_snapshot_id,
      candidate_profile_version_id, scoring_rubric_version_id,
      score, confidence, rationale, strengths, gaps, constraints, assessed_at, provenance
    ) values (
      v_owner_id, v_job_id, v_snapshot_id, v_profile_id, v_rubric_id,
      (v_role ->> 'score')::numeric, (v_role ->> 'confidence')::numeric,
      nullif(v_role ->> 'rationale', ''), coalesce(v_role -> 'strengths', '[]'::jsonb),
      coalesce(v_role -> 'gaps', '[]'::jsonb), coalesce(v_role -> 'constraints', '[]'::jsonb),
      (v_role ->> 'assessed_at')::timestamptz,
      jsonb_build_object(
        'source_url', v_role ->> 'source_url',
        'execution_id', v_execution_id,
        'score_label', 'profile-to-role fit score',
        'not_hiring_probability', true,
        'reassessment', true,
        'geography_rule', p_run ->> 'geography_rule'
      )
    )
    on conflict (owner_id, job_posting_id, job_description_snapshot_id, candidate_profile_version_id, scoring_rubric_version_id)
      where job_description_snapshot_id is not null
    do nothing
    returning id into v_assessment_id;

    if v_assessment_id is null then
      select id into v_assessment_id
      from public.fit_assessments
      where owner_id = v_owner_id and job_posting_id = v_job_id
        and job_description_snapshot_id = v_snapshot_id
        and candidate_profile_version_id = v_profile_id
        and scoring_rubric_version_id = v_rubric_id
        and score = (v_role ->> 'score')::numeric
        and confidence = (v_role ->> 'confidence')::numeric
        and coalesce(rationale, '') = coalesce(v_role ->> 'rationale', '')
        and strengths = coalesce(v_role -> 'strengths', '[]'::jsonb)
        and gaps = coalesce(v_role -> 'gaps', '[]'::jsonb)
        and constraints = coalesce(v_role -> 'constraints', '[]'::jsonb);
      if v_assessment_id is null then
        raise exception 'posting was already reassessed with different evidence; use a new profile or rubric version' using errcode = '23505';
      end if;
    end if;

    v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'fit_assessment', 'id', v_assessment_id));
  end loop;

  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'record_job_reassessment_run', v_hash, v_result_ids);
  return public.read_back_job_reassessment_run(p_operation_key);
end;
$$;

revoke all on function public.record_job_reassessment_run(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_job_reassessment_run(text) from public, anon, authenticated;
grant execute on function public.record_job_reassessment_run(jsonb, text) to authenticated;
grant execute on function public.read_back_job_reassessment_run(text) to authenticated;

comment on function public.record_job_reassessment_run(jsonb, text) is
  'Creates versioned owner fit assessments against retained job-description snapshots; never creates or changes postings, applications, opportunities, tasks, or notifications.';
