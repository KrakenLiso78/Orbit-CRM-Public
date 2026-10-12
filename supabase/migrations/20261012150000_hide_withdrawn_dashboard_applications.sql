-- FR-058: preserve null states while excluding rejected and withdrawn before LIMIT.
do $$
declare definition text; updated_definition text;
begin
 definition:=pg_get_functiondef('public.get_dashboard_snapshot(integer,integer)'::regprocedure);
 updated_definition:=replace(definition,
  'and current_state.event_type is distinct from ''rejected''',
  'and (current_state.event_type is null or current_state.event_type not in (''rejected'', ''withdrawn''))');
 if updated_definition=definition then raise exception 'Expected application filter not found'; end if;
 execute updated_definition;
end;
$$;
