-- Unified, owner-scoped post-submission application history.
-- Activities and explanatory amendments must not replace lifecycle outcomes.
create or replace view public.current_application_states
with (security_invoker = true)
as
select distinct on (a.owner_id, a.id)
  a.owner_id, a.id as application_id, e.event_type as current_state,
  e.occurred_at as state_recorded_at, e.id as application_event_id
from public.applications a
left join public.application_events e
  on e.owner_id = a.owner_id and e.application_id = a.id
 and e.event_type in ('submitted', 'interview', 'withdrawn', 'rejected', 'offer', 'accepted', 'reopened')
order by a.owner_id, a.id, e.occurred_at desc nulls last, e.created_at desc, e.id desc;

create or replace function public.resolve_application(
  p_application_id uuid default null, p_company_name text default null,
  p_role_title text default null, p_source_identifier text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_results jsonb;
  v_count integer;
begin
  if p_limit is null or p_limit < 1 or p_limit > 20 then
    raise exception 'limit must be between 1 and 20' using errcode = '22023';
  end if;
  if p_application_id is null and nullif(btrim(p_company_name), '') is null
     and nullif(btrim(p_role_title), '') is null and nullif(btrim(p_source_identifier), '') is null then
    raise exception 'an application identity filter is required' using errcode = '22023';
  end if;
  with matches as (
    select a.id as application_id, c.name as company_name,
      coalesce(j.title, o.title) as role_title, a.submitted_at, a.channel,
      a.source_identifier, a.source_url, s.current_state,
      (select e.id from public.application_events e
        where e.owner_id = v_owner and e.application_id = a.id
        order by e.created_at desc, e.id desc limit 1) as latest_event_id
    from public.applications a
    join public.companies c on c.owner_id = a.owner_id and c.id = a.company_id
    left join public.opportunities o on o.owner_id = a.owner_id and o.id = a.opportunity_id
    left join public.job_postings j on j.owner_id = a.owner_id and j.id = a.job_posting_id
    left join public.current_application_states s on s.owner_id = a.owner_id and s.application_id = a.id
    where a.owner_id = v_owner
      and (p_application_id is null or a.id = p_application_id)
      and (nullif(btrim(p_company_name), '') is null or lower(c.name) = lower(btrim(p_company_name)))
      and (nullif(btrim(p_role_title), '') is null or lower(j.title) = lower(btrim(p_role_title)) or lower(o.title) = lower(btrim(p_role_title)))
      and (nullif(btrim(p_source_identifier), '') is null or a.source_identifier = btrim(p_source_identifier))
  ), bounded as (
    select * from matches order by submitted_at desc, application_id limit p_limit
  )
  select (select count(*) from matches), coalesce(jsonb_agg(to_jsonb(bounded) order by submitted_at desc, application_id), '[]'::jsonb)
    into v_count, v_results from bounded;
  return jsonb_build_object('saved', false, 'candidates', v_results,
    'match_count', v_count, 'truncated', v_count > p_limit,
    'resolved', v_count = 1);
end;
$$;

create or replace function public.read_back_application_event(p_operation_key text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
  v_event public.application_events%rowtype;
begin
  select * into v_receipt from public.operation_receipts
    where owner_id = v_owner and operation_key = p_operation_key
      and operation_type = 'record_application_event';
  if not found then
    raise exception 'application event receipt was not found' using errcode = 'P0002';
  end if;
  select e.* into v_event from public.application_events e
    where e.owner_id = v_owner and e.id = (
      select (entry ->> 'id')::uuid from jsonb_array_elements(v_receipt.result_record_ids) entry
      where entry ->> 'type' = 'application_event'
    );
  if not found then
    raise exception 'application event readback failed' using errcode = 'P0002';
  end if;
  return jsonb_build_object('saved', true,
    'receipt', to_jsonb(v_receipt) - 'owner_id',
    'event', to_jsonb(v_event) - 'owner_id',
    'application', (select to_jsonb(a) - 'owner_id' from public.applications a
      where a.owner_id = v_owner and a.id = v_event.application_id),
    'current_state', (select to_jsonb(s) - 'owner_id' from public.current_application_states s
      where s.owner_id = v_owner and s.application_id = v_event.application_id));
end;
$$;

create or replace function public.record_application_event(p_event jsonb, p_operation_key text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_application public.applications%rowtype;
  v_receipt public.operation_receipts%rowtype;
  v_latest uuid;
  v_expected uuid;
  v_type text;
  v_at timestamptz;
  v_note text;
  v_url text;
  v_hash text;
  v_key text;
  v_state text;
  v_state_at timestamptz;
  v_id uuid;
begin
  if p_event is null or jsonb_typeof(p_event) is distinct from 'object'
     or nullif(btrim(p_operation_key), '') is null then
    raise exception 'event object and operation_key are required' using errcode = '22023';
  end if;
  for v_key in select jsonb_object_keys(p_event) loop
    if v_key not in ('application_id', 'expected_latest_event_id', 'event_type', 'occurred_at', 'note', 'evidence_url') then
      raise exception 'unsupported application event field: %', v_key using errcode = '22023';
    end if;
  end loop;
  foreach v_key in array array['application_id', 'event_type', 'occurred_at', 'note'] loop
    if jsonb_typeof(p_event -> v_key) is distinct from 'string'
       or nullif(btrim(p_event ->> v_key), '') is null then
      raise exception 'non-empty string required: %', v_key using errcode = '22023';
    end if;
  end loop;
  if not (p_event ? 'expected_latest_event_id')
     or jsonb_typeof(p_event -> 'expected_latest_event_id') not in ('string', 'null') then
    raise exception 'expected_latest_event_id is required (UUID or explicit null)' using errcode = '22023';
  end if;
  if p_event ? 'evidence_url' and jsonb_typeof(p_event -> 'evidence_url') not in ('string', 'null') then
    raise exception 'evidence_url must be a string or null' using errcode = '22023';
  end if;
  v_type := p_event ->> 'event_type';
  if v_type not in ('follow_up', 'interview', 'withdrawn', 'rejected', 'offer', 'accepted', 'reopened', 'correction', 'other') then
    raise exception 'unsupported post-submission event type' using errcode = '22023';
  end if;
  v_expected := (p_event ->> 'expected_latest_event_id')::uuid;
  if (p_event ->> 'occurred_at') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'occurred_at must be an ISO timestamp with timezone' using errcode = '22023';
  end if;
  v_at := (p_event ->> 'occurred_at')::timestamptz;
  v_note := btrim(p_event ->> 'note');
  v_url := nullif(btrim(p_event ->> 'evidence_url'), '');
  if v_url is not null and v_url !~ '^https?://[^[:space:]]+$' then
    raise exception 'evidence_url must be an HTTP(S) URL' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(convert_to(p_event::text, 'UTF8'), 'sha256'), 'hex');
  -- One application lock serializes competing lifecycle writes and exact retries.
  select * into v_application from public.applications
    where owner_id = v_owner and id = (p_event ->> 'application_id')::uuid for update;
  if not found then
    raise exception 'application not found for authenticated owner' using errcode = '42501';
  end if;
  select * into v_receipt from public.operation_receipts
    where owner_id = v_owner and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_application_event' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_application_event(p_operation_key);
  end if;
  select id into v_latest from public.application_events
    where owner_id = v_owner and application_id = v_application.id
    order by created_at desc, id desc limit 1;
  if v_latest is distinct from v_expected then
    raise exception 'application history changed; resolve again before recording' using errcode = 'PT409';
  end if;
  if not isfinite(v_at) or v_at < v_application.submitted_at or v_at > clock_timestamp() then
    raise exception 'event must occur between submission and now' using errcode = '22023';
  end if;
  if exists (select 1 from public.application_events where owner_id = v_owner
    and application_id = v_application.id and event_type = v_type and occurred_at = v_at
    and note is not distinct from v_note and evidence_url is not distinct from v_url) then
    raise exception 'this application event is already recorded' using errcode = '23505';
  end if;
  select current_state, state_recorded_at into v_state, v_state_at
    from public.current_application_states where owner_id = v_owner and application_id = v_application.id;
  if v_type not in ('follow_up', 'correction', 'other') then
    if v_state_at is not null and v_at <= v_state_at then
      raise exception 'state event must be later than the current state' using errcode = '22023';
    end if;
    if v_type = 'reopened' then
      if v_state is null or v_state not in ('withdrawn', 'rejected', 'accepted') then
        raise exception 'only a closed application can be reopened' using errcode = '22023';
      end if;
    elsif v_state in ('withdrawn', 'rejected', 'accepted') then
      raise exception 'closed application requires explicit reopening' using errcode = '22023';
    elsif v_type = 'accepted' and v_state is distinct from 'offer' then
      raise exception 'acceptance requires a recorded offer' using errcode = '22023';
    end if;
  end if;
  insert into public.application_events(owner_id, application_id, event_type, occurred_at, note, evidence_url, operation_key, created_at)
    values(v_owner, v_application.id, v_type, v_at, v_note, v_url, p_operation_key || ':event', clock_timestamp()) returning id into v_id;
  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
    values(v_owner, p_operation_key, 'record_application_event', v_hash,
      jsonb_build_array(jsonb_build_object('type', 'application', 'id', v_application.id),
        jsonb_build_object('type', 'application_event', 'id', v_id)));
  return public.read_back_application_event(p_operation_key);
end;
$$;

revoke all on function public.resolve_application(uuid,text,text,text,integer) from public, anon, authenticated;
revoke all on function public.record_application_event(jsonb,text) from public, anon, authenticated;
revoke all on function public.read_back_application_event(text) from public, anon, authenticated;
grant execute on function public.resolve_application(uuid,text,text,text,integer) to authenticated;
grant execute on function public.record_application_event(jsonb,text) to authenticated;
grant execute on function public.read_back_application_event(text) to authenticated;
comment on function public.record_application_event(jsonb,text) is
  'One atomic owner-scoped post-submission event writer with history concurrency, transition validation, idempotency receipt, and authoritative readback.';
