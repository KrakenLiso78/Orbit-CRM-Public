-- Owner-scoped Call Report API. Direct CRM table writes remain unavailable to
-- authenticated clients; this explicit RPC surface is the only write route.

-- Supabase's RLS event-trigger helper is not an API operation. Its default
-- PUBLIC EXECUTE grant is unnecessary and is removed without changing grants
-- for unrelated functions.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end;
$$;

create or replace function private.require_call_report_owner()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := auth.uid();
begin
  if v_owner_id is null then
    raise exception 'authenticated owner is required' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.crm_owner_profiles where owner_id = v_owner_id
  ) then
    raise exception 'authenticated user is not an Orbit CRM owner' using errcode = '42501';
  end if;

  return v_owner_id;
end;
$$;

create or replace function private.validate_interaction_capture(p_capture jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_context jsonb;
  v_follow_up jsonb;
  v_source jsonb;
begin
  if jsonb_typeof(p_capture) <> 'object' then
    raise exception 'capture must be a JSON object' using errcode = '22023';
  end if;

  for v_key in select jsonb_object_keys(p_capture)
  loop
    if v_key not in (
      'title', 'interaction_type', 'occurred_at', 'summary', 'insight', 'result',
      'next_step', 'follow_up_at', 'context', 'contact_ids', 'follow_up', 'source'
    ) then
      raise exception 'unsupported capture field: %', v_key using errcode = '22023';
    end if;
  end loop;

  if jsonb_typeof(p_capture -> 'title') <> 'string'
     or btrim(p_capture ->> 'title') = '' then
    raise exception 'capture title is required' using errcode = '22023';
  end if;

  if jsonb_typeof(p_capture -> 'occurred_at') <> 'string' then
    raise exception 'capture occurred_at is required' using errcode = '22023';
  end if;
  perform (p_capture ->> 'occurred_at')::timestamptz;

  if jsonb_typeof(p_capture -> 'contact_ids') <> 'array'
     or jsonb_array_length(p_capture -> 'contact_ids') = 0 then
    raise exception 'capture requires at least one resolved contact ID' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements_text(p_capture -> 'contact_ids') as element(value)
    where element.value = ''
  ) then
    raise exception 'capture contact IDs must be UUID strings' using errcode = '22023';
  end if;
  perform element.value::uuid from jsonb_array_elements_text(p_capture -> 'contact_ids') as element(value);
  if (select count(*) from jsonb_array_elements_text(p_capture -> 'contact_ids'))
     <> (select count(distinct element.value) from jsonb_array_elements_text(p_capture -> 'contact_ids') as element(value)) then
    raise exception 'capture contact IDs must be distinct' using errcode = '22023';
  end if;

  v_context := p_capture -> 'context';
  if v_context is not null and jsonb_typeof(v_context) <> 'null' then
    if jsonb_typeof(v_context) <> 'object'
       or (select count(*) from jsonb_object_keys(v_context)) <> 1
       or exists (
         select 1 from jsonb_object_keys(v_context) as key
         where key not in ('company_id', 'opportunity_id', 'application_id')
       ) then
      raise exception 'context must contain exactly one supported context ID' using errcode = '22023';
    end if;
    perform value::uuid from jsonb_each_text(v_context) as entry(key, value);
  end if;

  v_follow_up := p_capture -> 'follow_up';
  if v_follow_up is not null and jsonb_typeof(v_follow_up) <> 'null' then
    if jsonb_typeof(v_follow_up) <> 'object'
       or jsonb_typeof(v_follow_up -> 'title') <> 'string'
       or btrim(v_follow_up ->> 'title') = ''
       or exists (
         select 1 from jsonb_object_keys(v_follow_up) as key
         where key not in ('title', 'task_type', 'authority_state', 'priority', 'due_at', 'notes', 'state', 'completed_at')
       ) then
      raise exception 'follow_up has an invalid shape' using errcode = '22023';
    end if;
    if coalesce(v_follow_up ->> 'authority_state', 'proposal') not in ('proposal', 'commitment')
       or (v_follow_up ? 'priority' and v_follow_up ->> 'priority' not in ('P0', 'P1', 'P2', 'P3'))
       or coalesce(v_follow_up ->> 'state', '0-Backlog') not in ('0-Backlog', '1-En curso', '2-Completada', '3-Bloqueada', '4-Cancelada') then
      raise exception 'follow_up contains an unsupported authority, priority, or state' using errcode = '22023';
    end if;
    if v_follow_up ? 'due_at' then
      perform (v_follow_up ->> 'due_at')::timestamptz;
    end if;
    if v_follow_up ? 'completed_at' then
      perform (v_follow_up ->> 'completed_at')::timestamptz;
    end if;
    if (v_follow_up ->> 'state' = '2-Completada') <> (v_follow_up ? 'completed_at') then
      raise exception 'completed follow_up requires completed_at, and only completed follow_up may set it' using errcode = '22023';
    end if;
    if coalesce(v_follow_up ->> 'authority_state', 'proposal') <> 'commitment'
       and v_follow_up ? 'due_at' then
      raise exception 'proposal follow_up cannot have due_at' using errcode = '22023';
    end if;
  end if;

  v_source := p_capture -> 'source';
  if jsonb_typeof(v_source) <> 'object'
     or exists (
       select 1 from jsonb_object_keys(v_source) as key
       where key not in ('source_system', 'source_database', 'source_record_id', 'source_url', 'source_created_at', 'source_updated_at', 'source_sha256')
     )
     or jsonb_typeof(v_source -> 'source_system') <> 'string'
     or jsonb_typeof(v_source -> 'source_database') <> 'string'
     or jsonb_typeof(v_source -> 'source_record_id') <> 'string'
     or btrim(v_source ->> 'source_system') = ''
     or btrim(v_source ->> 'source_database') = ''
     or btrim(v_source ->> 'source_record_id') = '' then
    raise exception 'capture source_system, source_database, and source_record_id are required' using errcode = '22023';
  end if;
  if v_source ? 'source_created_at' then
    perform (v_source ->> 'source_created_at')::timestamptz;
  end if;
  if v_source ? 'source_updated_at' then
    perform (v_source ->> 'source_updated_at')::timestamptz;
  end if;
  if v_source ? 'source_sha256'
     and (v_source ->> 'source_sha256' !~ '^[0-9a-f]{64}$') then
    raise exception 'source_sha256 must be a lowercase SHA-256 hexadecimal digest' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.resolve_company(
  p_name text default null,
  p_website_url text default null,
  p_linkedin_url text default null,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
begin
  if p_limit < 1 or p_limit > 20
     or (nullif(btrim(p_name), '') is null and nullif(btrim(p_website_url), '') is null and nullif(btrim(p_linkedin_url), '') is null) then
    raise exception 'provide an identity field and a limit from 1 to 20' using errcode = '22023';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(company) - 'owner_id' order by company.name)
    from (
      select id, name, website_url, linkedin_url, careers_url, headquarters, priority, strategic_fit, archived_at, lock_version
      from public.companies
      where owner_id = v_owner_id
        and archived_at is null
        and (
          (nullif(btrim(p_website_url), '') is not null and lower(website_url) = lower(btrim(p_website_url)))
          or (nullif(btrim(p_linkedin_url), '') is not null and lower(linkedin_url) = lower(btrim(p_linkedin_url)))
          or (nullif(btrim(p_name), '') is not null and normalized_name = lower(btrim(p_name)))
        )
      order by name
      limit p_limit
    ) as company
  ), '[]'::jsonb);
end;
$$;

create or replace function public.resolve_contact(
  p_name text default null,
  p_email text default null,
  p_linkedin_url text default null,
  p_limit integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
begin
  if p_limit < 1 or p_limit > 20
     or (nullif(btrim(p_name), '') is null and nullif(btrim(p_email), '') is null and nullif(btrim(p_linkedin_url), '') is null) then
    raise exception 'provide an identity field and a limit from 1 to 20' using errcode = '22023';
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(contact) - 'owner_id' order by contact.name)
    from (
      select id, name, email, linkedin_url, job_title, location, priority, relationship_state, archived_at, lock_version
      from public.contacts
      where owner_id = v_owner_id
        and archived_at is null
        and (
          (nullif(btrim(p_email), '') is not null and lower(email) = lower(btrim(p_email)))
          or (nullif(btrim(p_linkedin_url), '') is not null and lower(linkedin_url) = lower(btrim(p_linkedin_url)))
          or (nullif(btrim(p_name), '') is not null and lower(btrim(name)) = lower(btrim(p_name)))
        )
      order by name
      limit p_limit
    ) as contact
  ), '[]'::jsonb);
end;
$$;

create or replace function public.prepare_interaction_capture(p_capture jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_contact_ids uuid[];
  v_context jsonb := p_capture -> 'context';
begin
  perform private.validate_interaction_capture(p_capture);
  select array_agg(element.value::uuid order by element.value::uuid)
    into v_contact_ids
    from jsonb_array_elements_text(p_capture -> 'contact_ids') as element(value);

  if (select count(*) from public.contacts where owner_id = v_owner_id and id = any(v_contact_ids)) <> cardinality(v_contact_ids) then
    raise exception 'one or more contact IDs are not owned by the authenticated owner' using errcode = '42501';
  end if;
  if v_context ? 'company_id' and not exists (select 1 from public.companies where owner_id = v_owner_id and id = (v_context ->> 'company_id')::uuid) then
    raise exception 'context company is not owned by the authenticated owner' using errcode = '42501';
  end if;
  if v_context ? 'opportunity_id' and not exists (select 1 from public.opportunities where owner_id = v_owner_id and id = (v_context ->> 'opportunity_id')::uuid) then
    raise exception 'context opportunity is not owned by the authenticated owner' using errcode = '42501';
  end if;
  if v_context ? 'application_id' and not exists (select 1 from public.applications where owner_id = v_owner_id and id = (v_context ->> 'application_id')::uuid) then
    raise exception 'context application is not owned by the authenticated owner' using errcode = '42501';
  end if;

  return jsonb_build_object('prepared', true, 'saved', false, 'contact_ids', to_jsonb(v_contact_ids));
end;
$$;

create or replace function public.record_interaction_capture(p_capture jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_request_sha256 text;
  v_receipt public.operation_receipts%rowtype;
  v_contact_ids uuid[];
  v_context jsonb := p_capture -> 'context';
  v_follow_up jsonb := p_capture -> 'follow_up';
  v_source jsonb := p_capture -> 'source';
  v_interaction_id uuid;
  v_task_id uuid;
  v_result_ids jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null then
    raise exception 'operation_key is required' using errcode = '22023';
  end if;
  perform private.validate_interaction_capture(p_capture);
  v_request_sha256 := encode(extensions.digest(convert_to(p_capture::text, 'UTF8'), 'sha256'), 'hex');

  insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256)
  values (v_owner_id, p_operation_key, 'record_interaction_capture', v_request_sha256)
  on conflict (owner_id, operation_key) do nothing
  returning * into v_receipt;
  if not found then
    select * into v_receipt
      from public.operation_receipts
      where owner_id = v_owner_id and operation_key = p_operation_key;
    if v_receipt.operation_type <> 'record_interaction_capture' or v_receipt.request_sha256 <> v_request_sha256 then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_interaction_capture(p_operation_key);
  end if;

  select array_agg(element.value::uuid order by element.value::uuid)
    into v_contact_ids
    from jsonb_array_elements_text(p_capture -> 'contact_ids') as element(value);
  if (select count(*) from public.contacts where owner_id = v_owner_id and id = any(v_contact_ids)) <> cardinality(v_contact_ids) then
    raise exception 'one or more contact IDs are not owned by the authenticated owner' using errcode = '42501';
  end if;
  if v_context ? 'company_id' and not exists (select 1 from public.companies where owner_id = v_owner_id and id = (v_context ->> 'company_id')::uuid) then
    raise exception 'context company is not owned by the authenticated owner' using errcode = '42501';
  end if;
  if v_context ? 'opportunity_id' and not exists (select 1 from public.opportunities where owner_id = v_owner_id and id = (v_context ->> 'opportunity_id')::uuid) then
    raise exception 'context opportunity is not owned by the authenticated owner' using errcode = '42501';
  end if;
  if v_context ? 'application_id' and not exists (select 1 from public.applications where owner_id = v_owner_id and id = (v_context ->> 'application_id')::uuid) then
    raise exception 'context application is not owned by the authenticated owner' using errcode = '42501';
  end if;

  insert into public.interactions (
    owner_id, title, interaction_type, occurred_at, summary, insight, result, next_step, follow_up_at,
    context_company_id, context_opportunity_id, context_application_id
  ) values (
    v_owner_id, btrim(p_capture ->> 'title'), nullif(btrim(p_capture ->> 'interaction_type'), ''),
    (p_capture ->> 'occurred_at')::timestamptz, nullif(p_capture ->> 'summary', ''), nullif(p_capture ->> 'insight', ''),
    nullif(p_capture ->> 'result', ''), nullif(p_capture ->> 'next_step', ''),
    nullif(p_capture ->> 'follow_up_at', '')::timestamptz,
    case when v_context ? 'company_id' then (v_context ->> 'company_id')::uuid end,
    case when v_context ? 'opportunity_id' then (v_context ->> 'opportunity_id')::uuid end,
    case when v_context ? 'application_id' then (v_context ->> 'application_id')::uuid end
  ) returning id into v_interaction_id;

  insert into public.interaction_contacts (owner_id, interaction_id, contact_id)
    select v_owner_id, v_interaction_id, unnest(v_contact_ids);

  insert into public.source_records (
    owner_id, source_system, source_database, source_record_id, source_url,
    source_created_at, source_updated_at, source_sha256, reconciliation_state, interaction_id
  ) values (
    v_owner_id, btrim(v_source ->> 'source_system'), btrim(v_source ->> 'source_database'), btrim(v_source ->> 'source_record_id'),
    nullif(v_source ->> 'source_url', ''), nullif(v_source ->> 'source_created_at', '')::timestamptz,
    nullif(v_source ->> 'source_updated_at', '')::timestamptz, nullif(v_source ->> 'source_sha256', ''), 'mapped', v_interaction_id
  );

  v_result_ids := jsonb_build_array(jsonb_build_object('type', 'interaction', 'id', v_interaction_id));
  if v_follow_up is not null and jsonb_typeof(v_follow_up) <> 'null' then
    insert into public.tasks (
      owner_id, title, task_type, state, authority_state, priority, due_at, notes, source_interaction_id,
      context_company_id, context_opportunity_id, context_application_id, completed_at
    ) values (
      v_owner_id, btrim(v_follow_up ->> 'title'), nullif(v_follow_up ->> 'task_type', ''),
      coalesce(v_follow_up ->> 'state', '0-Backlog'), coalesce(v_follow_up ->> 'authority_state', 'proposal'),
      nullif(v_follow_up ->> 'priority', ''), nullif(v_follow_up ->> 'due_at', '')::timestamptz,
      nullif(v_follow_up ->> 'notes', ''), v_interaction_id,
      case when v_context ? 'company_id' then (v_context ->> 'company_id')::uuid end,
      case when v_context ? 'opportunity_id' then (v_context ->> 'opportunity_id')::uuid end,
      case when v_context ? 'application_id' then (v_context ->> 'application_id')::uuid end,
      nullif(v_follow_up ->> 'completed_at', '')::timestamptz
    ) returning id into v_task_id;

    insert into public.task_contacts (owner_id, task_id, contact_id)
      select v_owner_id, v_task_id, unnest(v_contact_ids);
    insert into public.task_events (owner_id, task_id, event_type, occurred_at, operation_key)
      values (v_owner_id, v_task_id, 'created', timezone('utc', now()), p_operation_key || ':task-created');
    if v_follow_up ->> 'state' = '2-Completada' then
      insert into public.task_events (owner_id, task_id, event_type, occurred_at, operation_key)
        values (v_owner_id, v_task_id, 'completed', (v_follow_up ->> 'completed_at')::timestamptz, p_operation_key || ':task-completed');
    end if;
    v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'task', 'id', v_task_id));
  end if;

  update public.operation_receipts
     set result_record_ids = v_result_ids
   where owner_id = v_owner_id and operation_key = p_operation_key;

  return public.read_back_interaction_capture(p_operation_key);
end;
$$;

create or replace function public.read_back_interaction_capture(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_interaction_id uuid;
begin
  select (entry ->> 'id')::uuid into v_interaction_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id
     and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'record_interaction_capture'
     and entry ->> 'type' = 'interaction';
  if v_interaction_id is null then
    raise exception 'capture receipt was not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'saved', true,
    'receipt', (select to_jsonb(receipt) - 'owner_id' from public.operation_receipts receipt where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key),
    'interaction', (select to_jsonb(interaction) - 'owner_id' from public.interactions interaction where interaction.owner_id = v_owner_id and interaction.id = v_interaction_id),
    'contacts', coalesce((select jsonb_agg(to_jsonb(contact) - 'owner_id' order by contact.name) from public.interaction_contacts relation join public.contacts contact on contact.owner_id = relation.owner_id and contact.id = relation.contact_id where relation.owner_id = v_owner_id and relation.interaction_id = v_interaction_id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(to_jsonb(task) - 'owner_id' order by task.created_at) from public.tasks task where task.owner_id = v_owner_id and task.source_interaction_id = v_interaction_id), '[]'::jsonb),
    'task_events', coalesce((select jsonb_agg(to_jsonb(event) - 'owner_id' order by event.occurred_at, event.id) from public.task_events event join public.tasks task on task.owner_id = event.owner_id and task.id = event.task_id where event.owner_id = v_owner_id and task.source_interaction_id = v_interaction_id), '[]'::jsonb),
    'source_records', coalesce((select jsonb_agg(to_jsonb(source) - 'owner_id' order by source.created_at) from public.source_records source where source.owner_id = v_owner_id and source.interaction_id = v_interaction_id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.complete_task(
  p_task_id uuid,
  p_completed_at timestamptz,
  p_note text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_request_sha256 text := encode(extensions.digest(convert_to(jsonb_build_object('task_id', p_task_id, 'completed_at', p_completed_at, 'note', p_note)::text, 'UTF8'), 'sha256'), 'hex');
  v_receipt public.operation_receipts%rowtype;
begin
  if nullif(btrim(p_operation_key), '') is null or p_completed_at is null then
    raise exception 'operation_key and completed_at are required' using errcode = '22023';
  end if;
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'complete_task' or v_receipt.request_sha256 <> v_request_sha256 then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_task_completion(p_operation_key);
  end if;
  if not exists (select 1 from public.tasks where owner_id = v_owner_id and id = p_task_id and authority_state = 'commitment' and state <> '2-Completada') then
    raise exception 'task is not an incomplete owner commitment' using errcode = 'P0001';
  end if;
  insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'complete_task', v_request_sha256, jsonb_build_array(jsonb_build_object('type', 'task', 'id', p_task_id)));
  update public.tasks set state = '2-Completada', completed_at = p_completed_at where owner_id = v_owner_id and id = p_task_id;
  insert into public.task_events (owner_id, task_id, event_type, occurred_at, note, operation_key)
  values (v_owner_id, p_task_id, 'completed', p_completed_at, nullif(p_note, ''), p_operation_key || ':completed');
  return public.read_back_task_completion(p_operation_key);
end;
$$;

create or replace function public.read_back_task_completion(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_task_id uuid;
begin
  select (entry ->> 'id')::uuid into v_task_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'complete_task' and entry ->> 'type' = 'task';
  if v_task_id is null then
    raise exception 'task completion receipt was not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'saved', true,
    'receipt', (select to_jsonb(receipt) - 'owner_id' from public.operation_receipts receipt where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key),
    'task', (select to_jsonb(task) - 'owner_id' from public.tasks task where task.owner_id = v_owner_id and task.id = v_task_id),
    'contacts', coalesce((select jsonb_agg(to_jsonb(contact) - 'owner_id' order by contact.name) from public.task_contacts relation join public.contacts contact on contact.owner_id = relation.owner_id and contact.id = relation.contact_id where relation.owner_id = v_owner_id and relation.task_id = v_task_id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(event) - 'owner_id' order by event.occurred_at, event.id) from public.task_events event where event.owner_id = v_owner_id and event.task_id = v_task_id), '[]'::jsonb)
  );
end;
$$;

revoke all on function private.require_call_report_owner() from public, anon, authenticated;
revoke all on function private.validate_interaction_capture(jsonb) from public, anon, authenticated;
revoke all on function public.resolve_company(text, text, text, integer) from public, anon, authenticated;
revoke all on function public.resolve_contact(text, text, text, integer) from public, anon, authenticated;
revoke all on function public.prepare_interaction_capture(jsonb) from public, anon, authenticated;
revoke all on function public.record_interaction_capture(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_interaction_capture(text) from public, anon, authenticated;
revoke all on function public.complete_task(uuid, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.read_back_task_completion(text) from public, anon, authenticated;

grant execute on function public.resolve_company(text, text, text, integer) to authenticated;
grant execute on function public.resolve_contact(text, text, text, integer) to authenticated;
grant execute on function public.prepare_interaction_capture(jsonb) to authenticated;
grant execute on function public.record_interaction_capture(jsonb, text) to authenticated;
grant execute on function public.read_back_interaction_capture(text) to authenticated;
grant execute on function public.complete_task(uuid, timestamptz, text, text) to authenticated;
grant execute on function public.read_back_task_completion(text) to authenticated;

comment on function public.record_interaction_capture(jsonb, text) is
  'Atomic owner-scoped call-report capture. The operation key is idempotent and the result is read back from authoritative records.';
