create or replace function public.record_career_source_checks(p_checks jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_hash text;
  v_receipt public.operation_receipts%rowtype;
  v_check jsonb;
  v_source_id uuid;
  v_ids jsonb := '[]'::jsonb;
  v_checked_at timestamptz;
  v_outcome text;
begin
  if nullif(btrim(p_operation_key), '') is null or jsonb_typeof(p_checks) <> 'array' or jsonb_array_length(p_checks) = 0 then
    raise exception 'checks array and operation_key are required' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(convert_to(p_checks::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_career_source_checks' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_career_source_checks(p_operation_key);
  end if;
  for v_check in select value from jsonb_array_elements(p_checks)
  loop
    v_checked_at := (v_check ->> 'checked_at')::timestamptz;
    v_outcome := v_check ->> 'outcome';
    if coalesce(v_check ->> 'source_url', '') !~ '^https://' or v_outcome not in ('succeeded', 'unavailable', 'manual_review', 'failed') then
      raise exception 'each check requires an https source_url and a supported outcome' using errcode = '22023';
    end if;
    update public.career_sources set
      last_checked_at = v_checked_at,
      last_successful_at = case when v_outcome = 'succeeded' then v_checked_at else last_successful_at end,
      next_due_at = v_checked_at + make_interval(days => cadence_days),
      status = case when v_outcome in ('unavailable', 'manual_review') then v_outcome else status end,
      last_error = case when v_outcome = 'succeeded' then null else nullif(v_check ->> 'detail', '') end,
      updated_at = timezone('utc', now())
    where owner_id = v_owner_id and source_url = v_check ->> 'source_url'
    returning id into v_source_id;
    if v_source_id is null then raise exception 'career source was not found: %', v_check ->> 'source_url' using errcode = 'P0002'; end if;
    v_ids := v_ids || jsonb_build_array(jsonb_build_object('type', 'career_source', 'id', v_source_id));
  end loop;
  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'record_career_source_checks', v_hash, v_ids);
  return public.read_back_career_source_checks(p_operation_key);
end;
$$;

create or replace function public.read_back_career_source_checks(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
begin
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key and operation_type = 'record_career_source_checks';
  if not found then raise exception 'career source check receipt was not found' using errcode = 'P0002'; end if;
  return jsonb_build_object('saved', true, 'receipt', to_jsonb(v_receipt) - 'owner_id',
    'sources', coalesce((select jsonb_agg(to_jsonb(s) - 'owner_id' order by s.priority_rank)
      from public.career_sources s where s.owner_id = v_owner_id and s.id in
      (select (x ->> 'id')::uuid from jsonb_array_elements(v_receipt.result_record_ids) x where x ->> 'type' = 'career_source')), '[]'::jsonb));
end;
$$;

revoke all on function public.record_career_source_checks(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_career_source_checks(text) from public, anon, authenticated;
grant execute on function public.record_career_source_checks(jsonb, text) to authenticated;
grant execute on function public.read_back_career_source_checks(text) to authenticated;

comment on function public.record_career_source_checks(jsonb, text) is
  'Owner-scoped source freshness and outcome update with idempotency and authoritative readback.';
