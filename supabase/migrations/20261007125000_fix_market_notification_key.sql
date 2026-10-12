-- Correct text concatenation precedence in the market notification key.
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

