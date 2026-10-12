-- FR-058: filter current lifecycle status before the dashboard lane limit.
do $$
declare definition text; updated_definition text;
begin
  definition := pg_get_functiondef('public.get_dashboard_snapshot(integer,integer)'::regprocedure);
  updated_definition := replace(definition,
    'where a.owner_id = (select auth.uid())' || chr(10) || '        order by a.submitted_at',
    'where a.owner_id = (select auth.uid())' || chr(10) || '          and current_state.event_type is distinct from ''rejected''' || chr(10) || '        order by a.submitted_at');
  if updated_definition = definition then raise exception 'Expected application projection not found'; end if;
  execute updated_definition;
end;
$$;
