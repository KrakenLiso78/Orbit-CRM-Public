-- Rolled-back synthetic fixtures verify that day-based source cadence cannot
-- drift later than the fixed 12:00 Europe/Madrid monitor schedule.
begin;
set local statement_timeout = '15s';

create temporary table cadence_results (name text, passed boolean);

do $$
declare
  v_owner uuid := '81000000-0000-0000-0000-000000000009';
  v_company uuid := '82000000-0000-0000-0000-000000000009';
  v_daily_url text := 'https://example.invalid/calendar-daily';
  v_five_day_url text := 'https://example.invalid/calendar-five-day';
  v_dst_url text := 'https://example.invalid/calendar-dst';
  v_checks jsonb;
  v_first jsonb;
  v_replay jsonb;
begin
  insert into auth.users(id, aud, role) values(v_owner, 'authenticated', 'authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner);
  insert into public.companies(id, owner_id, name) values(v_company, v_owner, 'Synthetic cadence company');
  insert into public.career_sources(owner_id, company_id, source_name, source_url, cadence_days, priority_rank, next_due_at)
  values
    (v_owner, v_company, 'Synthetic daily source', v_daily_url, 1, 1, '2099-01-01T00:00:00Z'),
    (v_owner, v_company, 'Synthetic five-day source', v_five_day_url, 5, 2, '2099-01-01T00:00:00Z'),
    (v_owner, v_company, 'Synthetic DST source', v_dst_url, 2, 3, '2099-01-01T00:00:00Z');

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  v_checks := jsonb_build_array(
    jsonb_build_object('source_url', v_daily_url, 'checked_at', '2026-10-10T10:06:10Z', 'outcome', 'succeeded'),
    jsonb_build_object('source_url', v_five_day_url, 'checked_at', '2026-10-10T10:06:10Z', 'outcome', 'succeeded'),
    jsonb_build_object('source_url', v_dst_url, 'checked_at', '2026-10-24T10:06:10Z', 'outcome', 'succeeded')
  );
  v_first := public.record_career_source_checks(v_checks, 'synthetic-calendar-cadence-v1');
  v_replay := public.record_career_source_checks(v_checks, 'synthetic-calendar-cadence-v1');
  execute 'reset role';

  insert into cadence_results values
    ('Daily cadence is due at the next Madrid calendar midnight',
      (select next_due_at = '2026-10-10T22:00:00Z'::timestamptz from public.career_sources where source_url = v_daily_url)),
    ('Five-day cadence is due at the fifth Madrid calendar midnight',
      (select next_due_at = '2026-10-14T22:00:00Z'::timestamptz from public.career_sources where source_url = v_five_day_url)),
    ('Calendar cadence remains correct across the Madrid DST transition',
      (select next_due_at = '2026-10-25T23:00:00Z'::timestamptz from public.career_sources where source_url = v_dst_url)),
    ('Authoritative readback is stable on exact replay', v_first = v_replay),
    ('Exact replay keeps one operation receipt',
      (select count(*) = 1 from public.operation_receipts where owner_id = v_owner and operation_key = 'synthetic-calendar-cadence-v1')),
    ('Anonymous clients cannot record source checks',
      not has_function_privilege('anon', 'public.record_career_source_checks(jsonb,text)'::regprocedure, 'execute')),
    ('Authenticated owners retain the reviewed source-check operation',
      has_function_privilege('authenticated', 'public.record_career_source_checks(jsonb,text)'::regprocedure, 'execute'));
end;
$$;

do $$
begin
  if exists(select 1 from cadence_results where passed is distinct from true) then
    raise exception 'career-source calendar cadence regression failed';
  end if;
end;
$$;

select name, passed from cadence_results order by name;
rollback;
