-- Synthetic acceptance fixtures; never persist test owners or CRM history.
begin;
set local statement_timeout = '15s';
create function pg_temp.assert_event_error(p_event jsonb, p_key text, p_code text)
returns void language plpgsql as $$
begin
  perform public.record_application_event(p_event, p_key);
  raise exception 'expected event failure %', p_code;
exception when others then
  if sqlstate <> p_code then raise; end if;
end;
$$;
grant execute on function pg_temp.assert_event_error(jsonb,text,text) to authenticated;
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_company uuid := gen_random_uuid();
  v_role uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_other_app uuid := gen_random_uuid();
  v_material uuid := gen_random_uuid();
  v_version uuid := gen_random_uuid();
  v_submitted timestamptz := now() - interval '10 days';
  v_before jsonb;
  v_first jsonb;
  v_again jsonb;
  v_event jsonb;
  v_result jsonb;
  v_latest uuid;
  v_step integer := 0;
  v_type text;
  v_state text;
  v_at timestamptz;
begin
  insert into auth.users(id, aud, role) values(v_owner, 'authenticated', 'authenticated'), (v_other, 'authenticated', 'authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner), (v_other);
  insert into public.companies(id, owner_id, name) values(v_company, v_owner, 'Synthetic application lifecycle');
  insert into public.opportunities(id, owner_id, company_id, title) values(v_role, v_owner, v_company, 'Synthetic role');
  insert into public.applications(id, owner_id, company_id, opportunity_id, submitted_at, channel, submission_evidence)
    values(v_app, v_owner, v_company, v_role, v_submitted, 'synthetic', 'Synthetic owner submission'),
      (v_other_app, v_owner, v_company, v_role, v_submitted, 'synthetic second submission', 'Synthetic second application');
  insert into public.materials(id, owner_id, name) values(v_material, v_owner, 'Synthetic immutable material');
  insert into public.material_versions(id, owner_id, material_id, version_label) values(v_version, v_owner, v_material, 'synthetic-v1');
  insert into public.application_material_versions(owner_id, application_id, material_version_id) values(v_owner, v_app, v_version);
  select to_jsonb(a) into v_before from public.applications a where id = v_app;
  insert into public.application_events(owner_id, application_id, event_type, occurred_at, note, operation_key)
    values(v_owner, v_app, 'submitted', v_submitted, 'Synthetic submission', 'synthetic-initial') returning id into v_latest;
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  v_result := public.resolve_application(p_company_name => 'Synthetic application lifecycle', p_role_title => 'Synthetic role');
  if (v_result ->> 'match_count')::integer <> 2 or (v_result ->> 'resolved')::boolean then
    raise exception 'Ambiguous applications must not resolve';
  end if;
  v_result := public.resolve_application(p_company_name => 'Synthetic application lifecycle', p_limit => 1);
  if not (v_result ->> 'truncated')::boolean or (v_result ->> 'match_count')::integer <> 2 then
    raise exception 'Resolver must disclose truncation';
  end if;
  v_result := public.resolve_application(p_application_id => v_app);
  if not (v_result ->> 'resolved')::boolean or (v_result #>> '{candidates,0,latest_event_id}')::uuid <> v_latest then
    raise exception 'Exact resolver failed';
  end if;
  v_event := jsonb_build_object('application_id', v_app, 'expected_latest_event_id', v_latest,
    'event_type', 'rejected', 'occurred_at', to_char(v_submitted + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS.USOF'), 'note', 'Synthetic owner reports rejection');
  -- Timestamp formatter uses +00; supply the unambiguous canonical UTC form.
  v_event := jsonb_set(v_event, '{occurred_at}', to_jsonb(to_char((v_submitted + interval '1 day') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')));
  perform pg_temp.assert_event_error(v_event || '{"event_type":"accepted"}', 'synthetic-no-offer', '22023');
  perform pg_temp.assert_event_error(v_event || '{"event_type":"submitted"}', 'synthetic-resubmit', '22023');
  perform pg_temp.assert_event_error(v_event || '{"owner_id":"bad"}', 'synthetic-fields', '22023');
  perform pg_temp.assert_event_error(v_event || '{"note":" "}', 'synthetic-no-note', '22023');
  perform pg_temp.assert_event_error(v_event - 'expected_latest_event_id', 'synthetic-no-concurrency', '22023');
  perform pg_temp.assert_event_error(v_event || '{"occurred_at":"2026-01-01"}', 'synthetic-no-timezone', '22023');
  perform pg_temp.assert_event_error(v_event || jsonb_build_object('occurred_at', to_char(now() + interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), 'synthetic-future', '22023');
  perform pg_temp.assert_event_error(v_event || jsonb_build_object('occurred_at', to_char(v_submitted - interval '1 day', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')), 'synthetic-before-submission', '22023');
  perform pg_temp.assert_event_error(v_event || '{"evidence_url":"javascript:bad"}', 'synthetic-url', '22023');
  perform pg_temp.assert_event_error(v_event || '{"event_type":"reopened"}', 'synthetic-active-reopen', '22023');
  perform pg_temp.assert_event_error(v_event || jsonb_build_object('occurred_at', to_char(v_submitted at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')), 'synthetic-same-state-time', '22023');
  v_first := public.record_application_event(v_event, 'synthetic-rejected');
  v_again := public.record_application_event(v_event, 'synthetic-rejected');
  if v_first is distinct from v_again or v_first #>> '{current_state,current_state}' <> 'rejected' then
    raise exception 'Rejection save/readback/replay failed';
  end if;
  if public.read_back_application_event('synthetic-rejected') is distinct from v_first then
    raise exception 'Readback differs';
  end if;
  perform pg_temp.assert_event_error(v_event || '{"note":"Changed payload"}', 'synthetic-rejected', '23505');
  perform pg_temp.assert_event_error(v_event || '{"event_type":"interview"}', 'synthetic-stale', 'PT409');
  v_latest := (v_first #>> '{event,id}')::uuid;
  v_event := v_event || jsonb_build_object('expected_latest_event_id', v_latest);
  perform pg_temp.assert_event_error(v_event, 'synthetic-duplicate', '23505');
  perform pg_temp.assert_event_error(v_event || '{"event_type":"interview"}', 'synthetic-closed', '22023');
  -- Every remaining allowed event, including non-state activities after closure.
  foreach v_type in array array['follow_up','correction','other','reopened','interview','offer','accepted','follow_up','reopened','withdrawn'] loop
    v_step := v_step + 1;
    v_at := v_submitted + interval '2 days' + v_step * interval '1 hour';
    v_event := jsonb_build_object('application_id', v_app, 'expected_latest_event_id', v_latest,
      'event_type', v_type, 'occurred_at', to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'note', 'Synthetic explicit event ' || v_step);
    v_result := public.record_application_event(v_event, 'synthetic-step-' || v_step);
    v_latest := (v_result #>> '{event,id}')::uuid;
    if v_type not in ('follow_up','correction','other') then v_state := v_type;
    elsif v_state is null then v_state := 'rejected'; end if;
    if v_result #>> '{current_state,current_state}' <> v_state then
      raise exception 'Incorrect state after %', v_type;
    end if;
  end loop;
  -- Historical activity is append-only and does not change withdrawal.
  v_event := v_event || jsonb_build_object('expected_latest_event_id', v_latest,
    'event_type', 'other', 'occurred_at', to_char((v_submitted + interval '1 hour') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
  v_result := public.record_application_event(v_event, 'synthetic-historical-activity');
  if v_result #>> '{current_state,current_state}' <> 'withdrawn' then raise exception 'Historical note changed outcome'; end if;
  if (select count(*) from public.application_events where application_id=v_app) <> 13 then
    raise exception 'Unexpected event count';
  end if;
  if (select to_jsonb(a) - 'owner_id' from public.applications a where id = v_app) is distinct from (v_before - 'owner_id')
     or not exists(select 1 from public.application_material_versions where application_id = v_app and material_version_id=v_version) then
    raise exception 'Original submission or material links changed';
  end if;
  execute 'reset role';
  -- Another registered owner must see no candidates and cannot mutate/read receipts.
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  execute 'set local role authenticated';
  if (public.resolve_application(p_application_id => v_app) ->> 'match_count')::integer <> 0 then raise exception 'Foreign application leaked'; end if;
  perform pg_temp.assert_event_error(v_event, 'synthetic-foreign-owner', '42501');
  begin
    perform public.read_back_application_event('synthetic-rejected');
    raise exception 'Foreign receipt leaked';
  exception when sqlstate 'P0002' then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  begin
    perform public.record_application_event(v_event, 'synthetic-anon');
    raise exception 'Anonymous event write succeeded';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  if has_function_privilege('anon','public.resolve_application(uuid,text,text,text,integer)','execute')
     or has_function_privilege('anon','public.read_back_application_event(text)','execute')
     or has_table_privilege('authenticated','public.application_events','insert') then
    raise exception 'Unexpected public/table write grants';
  end if;
  if exists(select 1 from public.operation_receipts where owner_id=v_owner and operation_key in
    ('synthetic-stale','synthetic-closed','synthetic-no-offer','synthetic-future','synthetic-duplicate')) then
    raise exception 'Failed operation left a receipt';
  end if;
  raise notice 'Application event regression passed (synthetic fixtures rolled back)';
end;
$$;
rollback;
