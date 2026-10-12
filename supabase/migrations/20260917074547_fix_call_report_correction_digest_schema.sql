-- pgcrypto is installed in the extensions schema while this RPC deliberately
-- runs with an empty search_path. Recompile the existing function definition
-- with only the digest call schema-qualified.
do $$
declare
  v_function_definition text;
begin
  select pg_get_functiondef(
    'public.correct_call_report_record(text, uuid, bigint, jsonb, text, jsonb, text)'::regprocedure
  )
    into v_function_definition;

  execute replace(
    v_function_definition,
    'encode(digest(convert_to(jsonb_build_object(',
    'encode(extensions.digest(convert_to(jsonb_build_object('
  );
end;
$$;
