-- Preserve approved version content and original timestamps on configuration reuse.
-- Existing signature, owner guard, grants, source updates, and receipt semantics remain intact.
create or replace function public.configure_job_monitor(
  p_profile jsonb,
  p_profile_label text,
  p_rubric jsonb,
  p_rubric_label text,
  p_sources jsonb,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_hash text;
  v_receipt public.operation_receipts%rowtype;
  v_profile_id uuid;
  v_rubric_id uuid;
  v_source jsonb;
  v_company_id uuid;
  v_source_id uuid;
  v_source_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null
     or nullif(btrim(p_profile_label), '') is null
     or nullif(btrim(p_rubric_label), '') is null
     or jsonb_typeof(p_profile) <> 'object'
     or jsonb_typeof(p_rubric) <> 'object'
     or jsonb_typeof(p_sources) <> 'array'
     or jsonb_array_length(p_sources) = 0 then
    raise exception 'profile, rubric, labels, sources, and operation_key are required' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'profile', p_profile, 'profile_label', btrim(p_profile_label),
    'rubric', p_rubric, 'rubric_label', btrim(p_rubric_label), 'sources', p_sources
  )::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_receipt from public.operation_receipts
   where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'configure_job_monitor' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_job_monitor_configuration(p_operation_key);
  end if;

  insert into public.candidate_profile_versions(owner_id, version_label, profile_data, approved_at)
  values (v_owner_id, btrim(p_profile_label), p_profile, timezone('utc', now()))
  on conflict (owner_id, version_label) do nothing;
  select id into v_profile_id from public.candidate_profile_versions
    where owner_id = v_owner_id and version_label = btrim(p_profile_label)
      and profile_data = p_profile;
  if v_profile_id is null then
    raise exception 'profile version label already exists with different evidence; use a new version label' using errcode = '23505';
  end if;

  insert into public.scoring_rubric_versions(owner_id, version_label, rubric_data)
  values (v_owner_id, btrim(p_rubric_label), p_rubric)
  on conflict (owner_id, version_label) do nothing;
  select id into v_rubric_id from public.scoring_rubric_versions
    where owner_id = v_owner_id and version_label = btrim(p_rubric_label)
      and rubric_data = p_rubric;
  if v_rubric_id is null then
    raise exception 'rubric version label already exists with different dimensions; use a new version label' using errcode = '23505';
  end if;

  for v_source in select value from jsonb_array_elements(p_sources)
  loop
    if jsonb_typeof(v_source) <> 'object'
       or nullif(btrim(v_source ->> 'company_name'), '') is null
       or nullif(btrim(v_source ->> 'source_name'), '') is null
       or coalesce(v_source ->> 'source_url', '') !~ '^https://'
       or coalesce((v_source ->> 'cadence_days')::integer, 0) not between 1 and 31
       or coalesce((v_source ->> 'priority_rank')::integer, 0) not between 1 and 100 then
      raise exception 'each source requires company_name, source_name, https source_url, cadence_days, and priority_rank' using errcode = '22023';
    end if;
    select id into v_company_id from public.companies
     where owner_id = v_owner_id and normalized_name = lower(btrim(v_source ->> 'company_name')) and archived_at is null;
    if v_company_id is null then
      raise exception 'company is not registered: %', v_source ->> 'company_name' using errcode = 'P0002';
    end if;
    insert into public.career_sources(
      owner_id, company_id, source_name, source_url, geography, source_scope,
      cadence_days, status, priority_rank, next_due_at
    ) values (
      v_owner_id, v_company_id, btrim(v_source ->> 'source_name'), btrim(v_source ->> 'source_url'),
      coalesce(nullif(btrim(v_source ->> 'geography'), ''), 'Global'),
      coalesce(nullif(btrim(v_source ->> 'source_scope'), ''), 'Official careers site'),
      (v_source ->> 'cadence_days')::integer,
      coalesce(nullif(btrim(v_source ->> 'status'), ''), 'active'),
      (v_source ->> 'priority_rank')::integer,
      timezone('utc', now())
    ) on conflict (owner_id, company_id, source_url) do update set
      source_name = excluded.source_name, geography = excluded.geography,
      source_scope = excluded.source_scope, cadence_days = excluded.cadence_days,
      status = excluded.status, priority_rank = excluded.priority_rank,
      updated_at = timezone('utc', now())
    returning id into v_source_id;
    v_source_ids := v_source_ids || jsonb_build_array(jsonb_build_object('type', 'career_source', 'id', v_source_id));
  end loop;

  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'configure_job_monitor', v_hash,
    jsonb_build_array(
      jsonb_build_object('type', 'candidate_profile_version', 'id', v_profile_id),
      jsonb_build_object('type', 'scoring_rubric_version', 'id', v_rubric_id)
    ) || v_source_ids);
  return public.read_back_job_monitor_configuration(p_operation_key);
end;
$$;

