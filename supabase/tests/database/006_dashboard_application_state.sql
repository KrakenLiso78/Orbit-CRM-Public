-- Verify the dashboard exposes owner application state without changing data.
begin;
set local statement_timeout = '15s';

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_company uuid := gen_random_uuid();
  v_application uuid := gen_random_uuid();
  v_snapshot jsonb;
  v_item jsonb;
begin
  insert into auth.users(id, aud, role)
    values(v_owner, 'authenticated', 'authenticated'), (v_other, 'authenticated', 'authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner), (v_other);
  insert into public.companies(id, owner_id, name)
    values(v_company, v_owner, 'Synthetic dashboard application');
  insert into public.applications(id, owner_id, company_id, submitted_at, channel, submission_evidence)
    values(v_application, v_owner, v_company, now() - interval '3 days', 'synthetic', 'Synthetic dashboard state');
  insert into public.application_events(owner_id, application_id, event_type, occurred_at, note, operation_key, created_at)
    values
      (v_owner, v_application, 'submitted', now() - interval '3 days', 'Synthetic submission', 'synthetic-dashboard-submitted', now() - interval '3 minutes'),
      (v_owner, v_application, 'rejected', now() - interval '2 days', 'Synthetic rejection', 'synthetic-dashboard-rejected', now() - interval '2 minutes'),
      (v_owner, v_application, 'follow_up', now() - interval '1 day', 'Synthetic follow-up after rejection', 'synthetic-dashboard-follow-up', now() - interval '1 minute');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  v_snapshot := public.get_dashboard_snapshot(8, 8);
  select value into v_item
  from jsonb_array_elements(v_snapshot -> 'recent_applications') value
  where value ->> 'id' = v_application::text;
  if v_item is null then raise exception 'Owner dashboard application is missing'; end if;
  if v_item ->> 'current_state' <> 'rejected' then
    raise exception 'Incorrect current state: %', v_item ->> 'current_state';
  end if;
  if v_item ->> 'latest_event_type' <> 'follow_up' then
    raise exception 'Incorrect latest event type: %', v_item ->> 'latest_event_type';
  end if;
  if v_item ->> 'latest_event_note' <> 'Synthetic follow-up after rejection' then
    raise exception 'Incorrect latest event note: %', v_item ->> 'latest_event_note';
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  execute 'set local role authenticated';
  v_snapshot := public.get_dashboard_snapshot(8, 8);
  if exists (
    select 1 from jsonb_array_elements(v_snapshot -> 'recent_applications') value
    where value ->> 'id' = v_application::text
  ) then
    raise exception 'Foreign dashboard application leaked';
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  begin
    perform public.get_dashboard_snapshot(8, 8);
    raise exception 'Anonymous dashboard execution succeeded';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'Dashboard application-state regression passed (synthetic fixtures rolled back)';
end;
$$;

rollback;
