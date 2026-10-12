-- FR-060: explicitly reported employer cancellation; no record backfill.
alter table public.application_events drop constraint application_events_event_type_check;
alter table public.application_events add constraint application_events_event_type_check
 check(event_type in ('submitted','follow_up','interview','withdrawn','cancelled','rejected','offer','accepted','reopened','correction','other'));
do $$
declare signature text; definition text;
begin
 foreach signature in array array['public.record_application_event(jsonb,text)','public.get_dashboard_snapshot(integer,integer)','public.get_application_register()'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  if position('''withdrawn''' in definition)=0 then raise exception 'Expected lifecycle definition missing: %',signature; end if;
  execute replace(definition,'''withdrawn''','''withdrawn'', ''cancelled''');
 end loop;
 select pg_get_viewdef('public.current_application_states'::regclass,true) into definition;
 execute 'create or replace view public.current_application_states with (security_invoker=true) as ' || replace(definition,'''withdrawn''::text','''withdrawn''::text, ''cancelled''::text');
end;
$$;
