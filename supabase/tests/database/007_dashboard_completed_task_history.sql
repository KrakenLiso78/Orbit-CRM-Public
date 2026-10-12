-- Verify completed-task history and source context without retaining fixtures.
begin;
set local statement_timeout = '15s';

do $$
declare
  v_owner uuid := gen_random_uuid();
  v_other uuid := gen_random_uuid();
  v_interaction uuid := gen_random_uuid();
  v_task uuid := gen_random_uuid();
  v_snapshot jsonb;
  v_item jsonb;
begin
  insert into auth.users(id, aud, role)
    values(v_owner, 'authenticated', 'authenticated'), (v_other, 'authenticated', 'authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner), (v_other);
  insert into public.interactions(id, owner_id, title, occurred_at)
    values(v_interaction, v_owner, 'Synthetic source interaction', now() - interval '3 days');
  insert into public.tasks(id, owner_id, title, state, authority_state, source_interaction_id, completed_at)
    values(v_task, v_owner, 'Synthetic completed follow-up', '2-Completada', 'commitment', v_interaction, now() - interval '1 day');
  insert into public.task_events(id, owner_id, task_id, event_type, occurred_at, note, operation_key)
    values
      (gen_random_uuid(), v_owner, v_task, 'created', now() - interval '2 days', 'Synthetic creation', 'synthetic-dashboard-task-created'),
      (gen_random_uuid(), v_owner, v_task, 'completed', now() - interval '1 day', 'Synthetic completion', 'synthetic-dashboard-task-completed');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  v_snapshot := public.get_dashboard_snapshot(8, 8);
  select value into v_item
  from jsonb_array_elements(v_snapshot -> 'recent_completed_tasks') value
  where value ->> 'id' = v_task::text;
  if v_item is null then raise exception 'Owner completed task is missing'; end if;
  if v_item ->> 'source_interaction_title' <> 'Synthetic source interaction' then
    raise exception 'Source interaction context is missing';
  end if;
  if jsonb_array_length(v_item -> 'events') <> 2 then
    raise exception 'Expected two task events';
  end if;
  if v_item #>> '{events,0,event_type}' <> 'created' or v_item #>> '{events,1,event_type}' <> 'completed' then
    raise exception 'Task events are not in chronological order';
  end if;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub', v_other::text, true);
  execute 'set local role authenticated';
  v_snapshot := public.get_dashboard_snapshot(8, 8);
  if exists (
    select 1 from jsonb_array_elements(v_snapshot -> 'recent_completed_tasks') value
    where value ->> 'id' = v_task::text
  ) then
    raise exception 'Foreign completed task leaked';
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  begin
    perform public.get_dashboard_snapshot(8, 8);
    raise exception 'Anonymous dashboard execution succeeded';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'Dashboard completed-task history regression passed (synthetic fixtures rolled back)';
end;
$$;

rollback;
