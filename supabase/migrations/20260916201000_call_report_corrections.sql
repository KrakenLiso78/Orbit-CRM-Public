-- Owner-scoped amendments for Call Report records. These are deliberately not
-- generic table writes: target types and mutable fields are fixed below.

create table public.crm_corrections (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  operation_key text not null check (btrim(operation_key) <> ''),
  target_type text not null check (target_type in ('company', 'contact', 'opportunity', 'interaction', 'task')),
  target_id uuid not null,
  expected_lock_version bigint not null check (expected_lock_version > 0),
  reason text not null check (btrim(reason) <> ''),
  source jsonb not null,
  before_data jsonb not null,
  after_data jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, operation_key)
);

create index crm_corrections_owner_target_created_idx
  on public.crm_corrections (owner_id, target_type, target_id, created_at desc);

alter table public.crm_corrections enable row level security;
alter table public.crm_corrections force row level security;

create policy crm_corrections_owner_select
  on public.crm_corrections for select to authenticated
  using (owner_id = auth.uid());

create or replace function private.validate_call_report_correction(
  p_target_type text,
  p_changes jsonb,
  p_reason text,
  p_source jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_value jsonb;
  v_allowed text[];
  v_array_fields text[];
begin
  if p_target_type not in ('company', 'contact', 'opportunity', 'interaction', 'task') then
    raise exception 'unsupported correction target type' using errcode = '22023';
  end if;
  if jsonb_typeof(p_changes) <> 'object' or p_changes = '{}'::jsonb then
    raise exception 'changes must be a non-empty JSON object' using errcode = '22023';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'correction reason is required' using errcode = '22023';
  end if;
  if jsonb_typeof(p_source) <> 'object'
     or exists (
       select 1 from jsonb_object_keys(p_source) as key
       where key not in ('source_system', 'source_database', 'source_record_id', 'source_url', 'source_created_at', 'source_updated_at', 'source_sha256')
     )
     or jsonb_typeof(p_source -> 'source_system') <> 'string'
     or jsonb_typeof(p_source -> 'source_database') <> 'string'
     or jsonb_typeof(p_source -> 'source_record_id') <> 'string'
     or btrim(p_source ->> 'source_system') = ''
     or btrim(p_source ->> 'source_database') = ''
     or btrim(p_source ->> 'source_record_id') = '' then
    raise exception 'correction source_system, source_database, and source_record_id are required' using errcode = '22023';
  end if;

  case p_target_type
    when 'company' then
      v_allowed := array['name','website_url','linkedin_url','careers_url','headquarters','size_band','priority','strategic_fit','fit_reason','notes','segments','markets','archived_at'];
      v_array_fields := array['segments','markets'];
    when 'contact' then
      v_allowed := array['name','email','phone','linkedin_url','job_title','location','contact_type','source_channel','relationship_strength','relationship_state','priority','strategic_value','territories','cadence_days','last_contact_at','next_follow_up_at','personalized_message','context_notes','archived_at'];
      v_array_fields := array['territories'];
    when 'opportunity' then
      v_allowed := array['title','status','priority','source_type','opened_on','last_movement_at','next_step_at','next_step','target_role','role_fit','sector_fit','risk_level','primary_risk','narratives','location','work_mode','estimated_compensation','notes','archived_at'];
      v_array_fields := array['narratives'];
    when 'interaction' then
      v_allowed := array['title','interaction_type','occurred_at','summary','insight','result','next_step','follow_up_at'];
      v_array_fields := array[]::text[];
    when 'task' then
      v_allowed := array['title','task_type','authority_state','priority','due_at','effort_minutes','energy_block','notes'];
      v_array_fields := array[]::text[];
  end case;

  for v_key, v_value in select key, value from jsonb_each(p_changes)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'unsupported correction field: %', v_key using errcode = '22023';
    end if;
    if v_key = any(v_array_fields) then
      if jsonb_typeof(v_value) <> 'array'
         or exists (
           select 1 from jsonb_array_elements(v_value) as element(value)
           where jsonb_typeof(element.value) <> 'string'
         ) then
        raise exception 'correction field % must be an array of strings', v_key using errcode = '22023';
      end if;
    elsif v_key in ('cadence_days', 'effort_minutes') then
      if jsonb_typeof(v_value) not in ('number', 'null') then
        raise exception 'correction field % must be a number or null', v_key using errcode = '22023';
      end if;
    elsif jsonb_typeof(v_value) not in ('string', 'null') then
      raise exception 'correction field % must be a string or null', v_key using errcode = '22023';
    end if;
  end loop;
end;
$$;

create or replace function public.correct_call_report_record(
  p_target_type text,
  p_target_id uuid,
  p_expected_lock_version bigint,
  p_changes jsonb,
  p_reason text,
  p_source jsonb,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_request_sha256 text;
  v_existing public.operation_receipts%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_rows integer;
  v_array text[];
begin
  if p_target_id is null or p_expected_lock_version is null or p_expected_lock_version < 1
     or nullif(btrim(p_operation_key), '') is null then
    raise exception 'target ID, expected lock version, and operation key are required' using errcode = '22023';
  end if;
  perform private.validate_call_report_correction(p_target_type, p_changes, p_reason, p_source);
  v_request_sha256 := encode(digest(convert_to(jsonb_build_object(
    'target_type', p_target_type, 'target_id', p_target_id, 'expected_lock_version', p_expected_lock_version,
    'changes', p_changes, 'reason', p_reason, 'source', p_source
  )::text, 'utf8'), 'sha256'), 'hex');

  select * into v_existing
    from public.operation_receipts
   where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_existing.operation_type <> 'correct_call_report_record' or v_existing.request_sha256 <> v_request_sha256 then
      raise exception 'operation key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_call_report_correction(p_operation_key);
  end if;

  case p_target_type
    when 'company' then
      select to_jsonb(company) - 'owner_id' into v_before from public.companies company where owner_id = v_owner_id and id = p_target_id;
      if v_before is null then raise exception 'company not found' using errcode = 'P0002'; end if;
      update public.companies c set
        name = case when p_changes ? 'name' then nullif(btrim(p_changes->>'name'), '') else c.name end,
        website_url = case when p_changes ? 'website_url' then p_changes->>'website_url' else c.website_url end,
        linkedin_url = case when p_changes ? 'linkedin_url' then p_changes->>'linkedin_url' else c.linkedin_url end,
        careers_url = case when p_changes ? 'careers_url' then p_changes->>'careers_url' else c.careers_url end,
        headquarters = case when p_changes ? 'headquarters' then p_changes->>'headquarters' else c.headquarters end,
        size_band = case when p_changes ? 'size_band' then p_changes->>'size_band' else c.size_band end,
        priority = case when p_changes ? 'priority' then p_changes->>'priority' else c.priority end,
        strategic_fit = case when p_changes ? 'strategic_fit' then p_changes->>'strategic_fit' else c.strategic_fit end,
        fit_reason = case when p_changes ? 'fit_reason' then p_changes->>'fit_reason' else c.fit_reason end,
        notes = case when p_changes ? 'notes' then p_changes->>'notes' else c.notes end,
        segments = case when p_changes ? 'segments' then array(select jsonb_array_elements_text(p_changes->'segments')) else c.segments end,
        markets = case when p_changes ? 'markets' then array(select jsonb_array_elements_text(p_changes->'markets')) else c.markets end,
        archived_at = case when p_changes ? 'archived_at' then (p_changes->>'archived_at')::timestamptz else c.archived_at end
       where c.owner_id = v_owner_id and c.id = p_target_id and c.lock_version = p_expected_lock_version;
      get diagnostics v_rows = row_count;
      select to_jsonb(company) - 'owner_id' into v_after from public.companies company where owner_id = v_owner_id and id = p_target_id;
    when 'contact' then
      select to_jsonb(contact) - 'owner_id' into v_before from public.contacts contact where owner_id = v_owner_id and id = p_target_id;
      if v_before is null then raise exception 'contact not found' using errcode = 'P0002'; end if;
      update public.contacts c set
        name = case when p_changes ? 'name' then nullif(btrim(p_changes->>'name'), '') else c.name end,
        email = case when p_changes ? 'email' then p_changes->>'email' else c.email end,
        phone = case when p_changes ? 'phone' then p_changes->>'phone' else c.phone end,
        linkedin_url = case when p_changes ? 'linkedin_url' then p_changes->>'linkedin_url' else c.linkedin_url end,
        job_title = case when p_changes ? 'job_title' then p_changes->>'job_title' else c.job_title end,
        location = case when p_changes ? 'location' then p_changes->>'location' else c.location end,
        contact_type = case when p_changes ? 'contact_type' then p_changes->>'contact_type' else c.contact_type end,
        source_channel = case when p_changes ? 'source_channel' then p_changes->>'source_channel' else c.source_channel end,
        relationship_strength = case when p_changes ? 'relationship_strength' then p_changes->>'relationship_strength' else c.relationship_strength end,
        relationship_state = case when p_changes ? 'relationship_state' then p_changes->>'relationship_state' else c.relationship_state end,
        priority = case when p_changes ? 'priority' then p_changes->>'priority' else c.priority end,
        strategic_value = case when p_changes ? 'strategic_value' then p_changes->>'strategic_value' else c.strategic_value end,
        territories = case when p_changes ? 'territories' then array(select jsonb_array_elements_text(p_changes->'territories')) else c.territories end,
        cadence_days = case when p_changes ? 'cadence_days' then (p_changes->>'cadence_days')::smallint else c.cadence_days end,
        last_contact_at = case when p_changes ? 'last_contact_at' then (p_changes->>'last_contact_at')::timestamptz else c.last_contact_at end,
        next_follow_up_at = case when p_changes ? 'next_follow_up_at' then (p_changes->>'next_follow_up_at')::timestamptz else c.next_follow_up_at end,
        personalized_message = case when p_changes ? 'personalized_message' then p_changes->>'personalized_message' else c.personalized_message end,
        context_notes = case when p_changes ? 'context_notes' then p_changes->>'context_notes' else c.context_notes end,
        archived_at = case when p_changes ? 'archived_at' then (p_changes->>'archived_at')::timestamptz else c.archived_at end
       where c.owner_id = v_owner_id and c.id = p_target_id and c.lock_version = p_expected_lock_version;
      get diagnostics v_rows = row_count;
      select to_jsonb(contact) - 'owner_id' into v_after from public.contacts contact where owner_id = v_owner_id and id = p_target_id;
    when 'opportunity' then
      select to_jsonb(opportunity) - 'owner_id' into v_before from public.opportunities opportunity where owner_id = v_owner_id and id = p_target_id;
      if v_before is null then raise exception 'opportunity not found' using errcode = 'P0002'; end if;
      update public.opportunities o set
        title = case when p_changes ? 'title' then nullif(btrim(p_changes->>'title'), '') else o.title end,
        status = case when p_changes ? 'status' then p_changes->>'status' else o.status end,
        priority = case when p_changes ? 'priority' then p_changes->>'priority' else o.priority end,
        source_type = case when p_changes ? 'source_type' then p_changes->>'source_type' else o.source_type end,
        opened_on = case when p_changes ? 'opened_on' then (p_changes->>'opened_on')::date else o.opened_on end,
        last_movement_at = case when p_changes ? 'last_movement_at' then (p_changes->>'last_movement_at')::timestamptz else o.last_movement_at end,
        next_step_at = case when p_changes ? 'next_step_at' then (p_changes->>'next_step_at')::timestamptz else o.next_step_at end,
        next_step = case when p_changes ? 'next_step' then p_changes->>'next_step' else o.next_step end,
        target_role = case when p_changes ? 'target_role' then p_changes->>'target_role' else o.target_role end,
        role_fit = case when p_changes ? 'role_fit' then p_changes->>'role_fit' else o.role_fit end,
        sector_fit = case when p_changes ? 'sector_fit' then p_changes->>'sector_fit' else o.sector_fit end,
        risk_level = case when p_changes ? 'risk_level' then p_changes->>'risk_level' else o.risk_level end,
        primary_risk = case when p_changes ? 'primary_risk' then p_changes->>'primary_risk' else o.primary_risk end,
        narratives = case when p_changes ? 'narratives' then array(select jsonb_array_elements_text(p_changes->'narratives')) else o.narratives end,
        location = case when p_changes ? 'location' then p_changes->>'location' else o.location end,
        work_mode = case when p_changes ? 'work_mode' then p_changes->>'work_mode' else o.work_mode end,
        estimated_compensation = case when p_changes ? 'estimated_compensation' then p_changes->>'estimated_compensation' else o.estimated_compensation end,
        notes = case when p_changes ? 'notes' then p_changes->>'notes' else o.notes end,
        archived_at = case when p_changes ? 'archived_at' then (p_changes->>'archived_at')::timestamptz else o.archived_at end
       where o.owner_id = v_owner_id and o.id = p_target_id and o.lock_version = p_expected_lock_version;
      get diagnostics v_rows = row_count;
      select to_jsonb(opportunity) - 'owner_id' into v_after from public.opportunities opportunity where owner_id = v_owner_id and id = p_target_id;
    when 'interaction' then
      select to_jsonb(interaction) - 'owner_id' into v_before from public.interactions interaction where owner_id = v_owner_id and id = p_target_id;
      if v_before is null then raise exception 'interaction not found' using errcode = 'P0002'; end if;
      update public.interactions i set
        title = case when p_changes ? 'title' then nullif(btrim(p_changes->>'title'), '') else i.title end,
        interaction_type = case when p_changes ? 'interaction_type' then p_changes->>'interaction_type' else i.interaction_type end,
        occurred_at = case when p_changes ? 'occurred_at' then (p_changes->>'occurred_at')::timestamptz else i.occurred_at end,
        summary = case when p_changes ? 'summary' then p_changes->>'summary' else i.summary end,
        insight = case when p_changes ? 'insight' then p_changes->>'insight' else i.insight end,
        result = case when p_changes ? 'result' then p_changes->>'result' else i.result end,
        next_step = case when p_changes ? 'next_step' then p_changes->>'next_step' else i.next_step end,
        follow_up_at = case when p_changes ? 'follow_up_at' then (p_changes->>'follow_up_at')::timestamptz else i.follow_up_at end
       where i.owner_id = v_owner_id and i.id = p_target_id and i.lock_version = p_expected_lock_version;
      get diagnostics v_rows = row_count;
      select to_jsonb(interaction) - 'owner_id' into v_after from public.interactions interaction where owner_id = v_owner_id and id = p_target_id;
    when 'task' then
      select to_jsonb(task) - 'owner_id' into v_before from public.tasks task where owner_id = v_owner_id and id = p_target_id;
      if v_before is null then raise exception 'task not found' using errcode = 'P0002'; end if;
      update public.tasks t set
        title = case when p_changes ? 'title' then nullif(btrim(p_changes->>'title'), '') else t.title end,
        task_type = case when p_changes ? 'task_type' then p_changes->>'task_type' else t.task_type end,
        authority_state = case when p_changes ? 'authority_state' then p_changes->>'authority_state' else t.authority_state end,
        priority = case when p_changes ? 'priority' then p_changes->>'priority' else t.priority end,
        due_at = case when p_changes ? 'due_at' then (p_changes->>'due_at')::timestamptz else t.due_at end,
        effort_minutes = case when p_changes ? 'effort_minutes' then (p_changes->>'effort_minutes')::integer else t.effort_minutes end,
        energy_block = case when p_changes ? 'energy_block' then p_changes->>'energy_block' else t.energy_block end,
        notes = case when p_changes ? 'notes' then p_changes->>'notes' else t.notes end
       where t.owner_id = v_owner_id and t.id = p_target_id and t.lock_version = p_expected_lock_version;
      get diagnostics v_rows = row_count;
      select to_jsonb(task) - 'owner_id' into v_after from public.tasks task where owner_id = v_owner_id and id = p_target_id;
  end case;

  if v_rows <> 1 then
    raise exception 'record changed since it was read; resolve it again before correcting' using errcode = '40001';
  end if;

  insert into public.crm_corrections (owner_id, operation_key, target_type, target_id, expected_lock_version, reason, source, before_data, after_data)
  values (v_owner_id, p_operation_key, p_target_type, p_target_id, p_expected_lock_version, btrim(p_reason), p_source, v_before, v_after);
  insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'correct_call_report_record', v_request_sha256,
    jsonb_build_array(jsonb_build_object('type', p_target_type, 'id', p_target_id), jsonb_build_object('type', 'correction', 'id', (select id from public.crm_corrections where owner_id = v_owner_id and operation_key = p_operation_key))));
  if p_target_type = 'task' then
    insert into public.task_events (owner_id, task_id, event_type, occurred_at, note, operation_key)
    values (v_owner_id, p_target_id, 'corrected', timezone('utc', now()), btrim(p_reason), p_operation_key);
  end if;
  return public.read_back_call_report_correction(p_operation_key);
end;
$$;

create or replace function public.read_back_call_report_correction(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_correction public.crm_corrections%rowtype;
  v_record jsonb;
begin
  select * into v_correction from public.crm_corrections
   where owner_id = v_owner_id and operation_key = p_operation_key;
  if not found then raise exception 'correction receipt not found' using errcode = 'P0002'; end if;
  case v_correction.target_type
    when 'company' then select to_jsonb(row) - 'owner_id' into v_record from public.companies row where row.owner_id = v_owner_id and row.id = v_correction.target_id;
    when 'contact' then select to_jsonb(row) - 'owner_id' into v_record from public.contacts row where row.owner_id = v_owner_id and row.id = v_correction.target_id;
    when 'opportunity' then select to_jsonb(row) - 'owner_id' into v_record from public.opportunities row where row.owner_id = v_owner_id and row.id = v_correction.target_id;
    when 'interaction' then select to_jsonb(row) - 'owner_id' into v_record from public.interactions row where row.owner_id = v_owner_id and row.id = v_correction.target_id;
    when 'task' then select to_jsonb(row) - 'owner_id' into v_record from public.tasks row where row.owner_id = v_owner_id and row.id = v_correction.target_id;
  end case;
  return jsonb_build_object(
    'saved', true,
    'correction', to_jsonb(v_correction) - 'owner_id',
    'record', v_record,
    'receipt', (select to_jsonb(receipt) - 'owner_id' from public.operation_receipts receipt where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key)
  );
end;
$$;

revoke all on table public.crm_corrections from public, anon, authenticated;
grant select on table public.crm_corrections to authenticated;
revoke all on function private.validate_call_report_correction(text, jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_call_report_correction(text) from public, anon, authenticated;
grant execute on function public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text) to authenticated;
grant execute on function public.read_back_call_report_correction(text) to authenticated;

comment on function public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text) is
  'Corrects one owner-scoped Call Report record through fixed fields, optimistic locking, immutable correction history, idempotency, and authoritative readback.';
