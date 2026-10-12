-- Preserve task transition fields; application events have a separate schema.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('public.get_crm_record_context(text,uuid)'::regprocedure);
  if position('from public.application_events e' in definition) = 0 then
    raise exception 'Expected application context branch not found';
  end if;
  definition := replace(definition,
    '''note'',e.note,''previous_state'',e.previous_state,''new_state'',e.new_state) item' || chr(10) || '      from public.application_events e',
    '''note'',e.note) item' || chr(10) || '      from public.application_events e');
  if definition = pg_get_functiondef('public.get_crm_record_context(text,uuid)'::regprocedure) then
    if position('''note'',e.note) item' || chr(10) || '      from public.application_events e' in definition) > 0 then
      return; -- The previous public migration already has the repaired projection.
    end if;
    raise exception 'Expected application event projection not found';
  end if;
  execute definition;
end;
$$;
