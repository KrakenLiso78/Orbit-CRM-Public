-- Run through SQL, not the REST API: regressions must not start retry storms.
-- All synthetic fixtures and business-operation results are rolled back.
begin;
set local statement_timeout = '10s';
do $$
declare
  v_owner uuid := gen_random_uuid();
  v_company uuid := gen_random_uuid();
  v_source jsonb := '{"source_system":"test","source_database":"regression","source_record_id":"conflict"}';
  v_first jsonb;
  v_replay jsonb;
begin
  insert into auth.users(id, aud, role) values(v_owner, 'authenticated', 'authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner);
  insert into public.companies(id, owner_id, name) values(v_company, v_owner, 'Synthetic conflict regression');
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  v_first := public.correct_call_report_record('company', v_company, 1,
    '{"notes":"verified"}', 'Synthetic test', v_source, 'cpu-regression-success');
  v_replay := public.correct_call_report_record('company', v_company, 1,
    '{"notes":"verified"}', 'Synthetic test', v_source, 'cpu-regression-success');
  if v_first is distinct from v_replay then
    raise exception 'Idempotent replay changed its result';
  end if;
  begin
    perform public.correct_call_report_record('company', v_company, 1,
      '{"notes":"must not persist"}', 'Synthetic stale test', v_source, 'cpu-regression-stale');
    raise exception 'Stale correction unexpectedly succeeded';
  exception when sqlstate 'PT409' then
    null;
  end;
  if (select notes from public.companies where id=v_company) <> 'verified'
     or exists(select 1 from public.operation_receipts where owner_id=v_owner and operation_key='cpu-regression-stale') then
    raise exception 'Stale correction persisted data';
  end if;
  execute 'reset role';
  if has_function_privilege('anon', 'public.correct_call_report_record(text,uuid,bigint,jsonb,text,jsonb,text)', 'execute') then
    raise exception 'Anonymous correction access must remain denied';
  end if;
end;
$$;
rollback;
