-- Private MVP monitoring slice for job discovery/fit assessment and market review.
-- All writes are exposed only through bounded owner-scoped RPCs with idempotent receipts.

alter table public.job_postings
  add column if not exists location text,
  add column if not exists work_arrangement text,
  add column if not exists posted_at timestamptz,
  add column if not exists closing_at timestamptz;

create unique index if not exists job_postings_owner_source_identity_idx
  on public.job_postings (owner_id, source_name, source_identifier)
  where source_name is not null and source_identifier is not null;

create unique index if not exists fit_assessments_versioned_snapshot_idx
  on public.fit_assessments (
    owner_id, job_posting_id, job_description_snapshot_id,
    candidate_profile_version_id, scoring_rubric_version_id
  )
  where job_description_snapshot_id is not null;

create table if not exists public.career_sources (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  company_id uuid not null,
  source_name text not null check (btrim(source_name) <> ''),
  source_url text not null check (source_url ~ '^https://'),
  geography text not null default 'Global' check (btrim(geography) <> ''),
  source_scope text not null default 'Official careers site' check (btrim(source_scope) <> ''),
  cadence_days integer not null check (cadence_days between 1 and 31),
  status text not null default 'active' check (status in ('active', 'manual_review', 'unavailable', 'paused')),
  priority_rank integer not null check (priority_rank between 1 and 100),
  last_checked_at timestamptz,
  last_successful_at timestamptz,
  next_due_at timestamptz,
  last_error text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, company_id, source_url),
  foreign key (owner_id, company_id) references public.companies(owner_id, id) on delete restrict
);

create table if not exists public.monitor_executions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  monitor_type text not null check (monitor_type in ('job_discovery', 'market_review')),
  execution_key text not null check (btrim(execution_key) <> ''),
  started_at timestamptz not null,
  completed_at timestamptz,
  status text not null check (status in ('running', 'succeeded', 'partial', 'failed')),
  scope jsonb not null default '{}'::jsonb check (jsonb_typeof(scope) = 'object'),
  summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
  failures jsonb not null default '[]'::jsonb check (jsonb_typeof(failures) = 'array'),
  scheduler text not null check (scheduler in ('manual', 'codex_local', 'sites', 'supabase')),
  dependency_note text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, execution_key)
);

create table if not exists public.private_notifications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  notification_key text not null check (btrim(notification_key) <> ''),
  notification_type text not null check (notification_type in ('job_shortlist', 'market_review', 'monitor_failure')),
  title text not null check (btrim(title) <> ''),
  body jsonb not null default '{}'::jsonb check (jsonb_typeof(body) = 'object'),
  state text not null default 'unread' check (state in ('unread', 'read', 'archived')),
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, notification_key)
);

create table if not exists public.market_review_signal_links (
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  monitor_execution_id uuid not null,
  market_signal_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, monitor_execution_id, market_signal_id),
  foreign key (owner_id, monitor_execution_id) references public.monitor_executions(owner_id, id) on delete cascade,
  foreign key (owner_id, market_signal_id) references public.market_signals(owner_id, id) on delete restrict
);

alter table public.career_sources enable row level security;
alter table public.career_sources force row level security;
alter table public.monitor_executions enable row level security;
alter table public.monitor_executions force row level security;
alter table public.private_notifications enable row level security;
alter table public.private_notifications force row level security;
alter table public.market_review_signal_links enable row level security;
alter table public.market_review_signal_links force row level security;

create policy career_sources_owner_select on public.career_sources
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy monitor_executions_owner_select on public.monitor_executions
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy private_notifications_owner_select on public.private_notifications
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy market_review_signal_links_owner_select on public.market_review_signal_links
  for select to authenticated using ((select auth.uid()) = owner_id);

revoke all on public.career_sources, public.monitor_executions, public.private_notifications from public, anon, authenticated;
revoke all on public.market_review_signal_links from public, anon, authenticated;
grant select on public.career_sources, public.monitor_executions, public.private_notifications to authenticated;
grant select on public.market_review_signal_links to authenticated;

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
  on conflict (owner_id, version_label) do update set profile_data = excluded.profile_data
  returning id into v_profile_id;

  insert into public.scoring_rubric_versions(owner_id, version_label, rubric_data)
  values (v_owner_id, btrim(p_rubric_label), p_rubric)
  on conflict (owner_id, version_label) do update set rubric_data = excluded.rubric_data
  returning id into v_rubric_id;

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

create or replace function public.read_back_job_monitor_configuration(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
begin
  select * into v_receipt from public.operation_receipts
   where owner_id = v_owner_id and operation_key = p_operation_key and operation_type = 'configure_job_monitor';
  if not found then raise exception 'job monitor configuration receipt was not found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'saved', true,
    'receipt', to_jsonb(v_receipt) - 'owner_id',
    'profile', (select to_jsonb(p) - 'owner_id' from public.candidate_profile_versions p
      where p.owner_id = v_owner_id and p.id = ((select e ->> 'id' from jsonb_array_elements(v_receipt.result_record_ids) e where e ->> 'type' = 'candidate_profile_version' limit 1))::uuid),
    'rubric', (select to_jsonb(r) - 'owner_id' from public.scoring_rubric_versions r
      where r.owner_id = v_owner_id and r.id = ((select e ->> 'id' from jsonb_array_elements(v_receipt.result_record_ids) e where e ->> 'type' = 'scoring_rubric_version' limit 1))::uuid),
    'sources', coalesce((select jsonb_agg(to_jsonb(s) - 'owner_id' order by s.priority_rank)
      from public.career_sources s where s.owner_id = v_owner_id and s.id in
      (select (e ->> 'id')::uuid from jsonb_array_elements(v_receipt.result_record_ids) e where e ->> 'type' = 'career_source')), '[]'::jsonb)
  );
end;
$$;

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

create or replace function public.read_back_job_monitor_run(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
begin
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key and operation_type = 'record_job_monitor_run';
  if not found then raise exception 'job monitor receipt was not found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'saved', true, 'receipt', to_jsonb(v_receipt) - 'owner_id',
    'execution', (select to_jsonb(e) - 'owner_id' from public.monitor_executions e where e.owner_id = v_owner_id and e.id =
      ((select x ->> 'id' from jsonb_array_elements(v_receipt.result_record_ids) x where x ->> 'type' = 'monitor_execution' limit 1))::uuid),
    'roles', coalesce((select jsonb_agg(jsonb_build_object(
      'job', to_jsonb(j) - 'owner_id', 'assessment', to_jsonb(a) - 'owner_id', 'company_name', c.name
    ) order by a.score desc nulls last)
      from public.fit_assessments a join public.job_postings j on j.owner_id = a.owner_id and j.id = a.job_posting_id
      join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
      where a.owner_id = v_owner_id and a.id in
      (select (x ->> 'id')::uuid from jsonb_array_elements(v_receipt.result_record_ids) x where x ->> 'type' = 'fit_assessment')), '[]'::jsonb)
  );
end;
$$;

create or replace function public.record_market_review_run(p_run jsonb, p_operation_key text)
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
  v_signal jsonb;
  v_signal_id uuid;
  v_notification_id uuid;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null or jsonb_typeof(p_run) <> 'object'
     or jsonb_typeof(p_run -> 'signals') <> 'array'
     or (p_run ->> 'status') not in ('succeeded', 'partial', 'failed') then
    raise exception 'run requires operation_key, status, and a signals array' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(convert_to(p_run::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_market_review_run' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_market_review_run(p_operation_key);
  end if;
  insert into public.monitor_executions(owner_id, monitor_type, execution_key, started_at, completed_at, status, scope, summary, failures, scheduler, dependency_note)
  values (v_owner_id, 'market_review', p_run ->> 'execution_key', (p_run ->> 'started_at')::timestamptz,
    (p_run ->> 'completed_at')::timestamptz, p_run ->> 'status', coalesce(p_run -> 'scope', '{}'::jsonb),
    coalesce(p_run -> 'summary', '{}'::jsonb), coalesce(p_run -> 'failures', '[]'::jsonb),
    coalesce(nullif(p_run ->> 'scheduler', ''), 'manual'), nullif(p_run ->> 'dependency_note', ''))
  returning id into v_execution_id;
  v_result_ids := jsonb_build_array(jsonb_build_object('type', 'monitor_execution', 'id', v_execution_id));
  for v_signal in select value from jsonb_array_elements(p_run -> 'signals')
  loop
    if nullif(btrim(v_signal ->> 'title'), '') is null or coalesce(v_signal ->> 'source_url', '') !~ '^https://'
       or nullif(v_signal ->> 'signal_date', '') is null then
      raise exception 'each signal requires title, date, and an https source URL' using errcode = '22023';
    end if;
    insert into public.market_signals(owner_id, title, signal_type, signal_date, source_url, relevance, state,
      search_implication, suggested_action, notes)
    values (v_owner_id, btrim(v_signal ->> 'title'), nullif(v_signal ->> 'signal_type', ''),
      (v_signal ->> 'signal_date')::date, btrim(v_signal ->> 'source_url'),
      coalesce(nullif(v_signal ->> 'relevance', ''), 'Media'), 'Nueva',
      nullif(v_signal ->> 'search_implication', ''), nullif(v_signal ->> 'suggested_action', ''),
      nullif(v_signal ->> 'notes', '')) returning id into v_signal_id;
    insert into public.market_review_signal_links(owner_id, monitor_execution_id, market_signal_id)
    values (v_owner_id, v_execution_id, v_signal_id);
    v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'market_signal', 'id', v_signal_id));
  end loop;
  insert into public.private_notifications(owner_id, notification_key, notification_type, title, body)
  values (v_owner_id, concat('market:', p_run ->> 'execution_key'), 'market_review',
    coalesce(nullif(p_run ->> 'title', ''), 'Market review'),
    jsonb_build_object('execution_id', v_execution_id, 'signal_count', jsonb_array_length(p_run -> 'signals'), 'status', p_run ->> 'status'))
  returning id into v_notification_id;
  v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'private_notification', 'id', v_notification_id));
  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'record_market_review_run', v_hash, v_result_ids);
  return public.read_back_market_review_run(p_operation_key);
end;
$$;

create or replace function public.read_back_market_review_run(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
begin
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key and operation_type = 'record_market_review_run';
  if not found then raise exception 'market review receipt was not found' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'saved', true, 'receipt', to_jsonb(v_receipt) - 'owner_id',
    'execution', (select to_jsonb(e) - 'owner_id' from public.monitor_executions e where e.owner_id = v_owner_id and e.id =
      ((select x ->> 'id' from jsonb_array_elements(v_receipt.result_record_ids) x where x ->> 'type' = 'monitor_execution' limit 1))::uuid),
    'signals', coalesce((select jsonb_agg(to_jsonb(s) - 'owner_id' order by s.signal_date desc)
      from public.market_signals s where s.owner_id = v_owner_id and s.id in
      (select (x ->> 'id')::uuid from jsonb_array_elements(v_receipt.result_record_ids) x where x ->> 'type' = 'market_signal')), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_orbit_mvp_snapshot(p_limit integer default 12)
returns jsonb
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'generated_at', timezone('utc', now()),
    'job_roles', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc nulls last, x.last_seen_at desc)
      from (select j.id, j.title, c.name company_name, j.location, j.work_arrangement, j.source_url,
        j.status, j.first_seen_at, j.last_seen_at, j.posted_at, j.closing_at,
        a.score, a.confidence, a.rationale, a.strengths, a.gaps, a.constraints, a.assessed_at
        from public.job_postings j join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
        join lateral (select fa.* from public.fit_assessments fa where fa.owner_id = j.owner_id and fa.job_posting_id = j.id order by fa.assessed_at desc limit 1) a on true
        where j.owner_id = (select auth.uid()) and j.status = 'open'
        order by a.score desc nulls last, j.last_seen_at desc limit greatest(1, least(coalesce(p_limit, 12), 50))) x), '[]'::jsonb),
    'market_signals', coalesce((select jsonb_agg(to_jsonb(x) order by x.signal_date desc, x.created_at desc)
      from (select s.id, s.title, s.signal_type, s.signal_date, s.source_url, s.relevance, s.state, s.search_implication, s.suggested_action, s.notes, s.created_at
        from public.market_signals s join public.market_review_signal_links l
          on l.owner_id = s.owner_id and l.market_signal_id = s.id
        where s.owner_id = (select auth.uid()) and s.state <> 'Archivada'
        order by signal_date desc, created_at desc limit greatest(1, least(coalesce(p_limit, 12), 50))) x), '[]'::jsonb),
    'executions', coalesce((select jsonb_agg(to_jsonb(x) order by x.started_at desc)
      from (select id, monitor_type, execution_key, started_at, completed_at, status, scope, summary, failures, scheduler, dependency_note
        from public.monitor_executions where owner_id = (select auth.uid()) order by started_at desc limit 10) x), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (select id, notification_type, title, body, state, created_at from public.private_notifications
        where owner_id = (select auth.uid()) and state = 'unread' order by created_at desc limit 20) x), '[]'::jsonb)
  );
$$;

revoke all on function public.configure_job_monitor(jsonb, text, jsonb, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_job_monitor_configuration(text) from public, anon, authenticated;
revoke all on function public.record_job_monitor_run(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_job_monitor_run(text) from public, anon, authenticated;
revoke all on function public.record_market_review_run(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_market_review_run(text) from public, anon, authenticated;
revoke all on function public.get_orbit_mvp_snapshot(integer) from public, anon;
grant execute on function public.configure_job_monitor(jsonb, text, jsonb, text, jsonb, text) to authenticated;
grant execute on function public.read_back_job_monitor_configuration(text) to authenticated;
grant execute on function public.record_job_monitor_run(jsonb, text) to authenticated;
grant execute on function public.read_back_job_monitor_run(text) to authenticated;
grant execute on function public.record_market_review_run(jsonb, text) to authenticated;
grant execute on function public.read_back_market_review_run(text) to authenticated;
grant execute on function public.get_orbit_mvp_snapshot(integer) to authenticated;

-- Internal helpers must not remain directly executable by authenticated clients.
revoke all on function public.prepare_interaction_capture_core(jsonb) from authenticated, anon, public;
revoke all on function public.record_interaction_capture_core(jsonb, text) from authenticated, anon, public;

comment on function public.record_job_monitor_run(jsonb, text) is
  'Validated, owner-scoped, idempotent job discovery and fit-assessment write with authoritative readback.';
comment on function public.record_market_review_run(jsonb, text) is
  'Validated, owner-scoped, idempotent market-review write with authoritative readback.';
comment on function public.get_orbit_mvp_snapshot(integer) is
  'Bounded owner-scoped portal read for current job, market, execution, and private-notification data.';
