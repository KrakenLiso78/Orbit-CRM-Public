-- A stale business version is not a retryable PostgreSQL serialization failure.
-- PostgREST 14 retries SQLSTATE 40001 indefinitely; return HTTP 409 instead.
-- Preserve the deployed body, privileges, owner checks, and idempotency logic.
do $$
declare
  v_definition text;
  v_old text := 'raise exception ''record changed since it was read; resolve it again before correcting'' using errcode = ''40001'';';
  v_new text := 'raise exception ''record changed since it was read; resolve it again before correcting'' using errcode = ''PT409'';';
begin
  select pg_get_functiondef(
    'public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text)'::regprocedure
  ) into v_definition;
  if strpos(v_definition, v_old) > 0 then
    execute replace(v_definition, v_old, v_new);
  elsif strpos(v_definition, v_new) = 0 then
    raise exception 'Unexpected correction function definition; review before changing';
  end if;
end;
$$;
