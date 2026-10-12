-- FR-061: priority urgency before the lane limit and in JSON order.
do $$
declare definition text; updated_definition text;
begin
 definition:=pg_get_functiondef('public.get_dashboard_snapshot(integer,integer)'::regprocedure);
 updated_definition:=replace(definition,
 'order by task_row.due_at nulls last, task_row.created_at desc',
 'order by case when task_row.priority ~ ''^P[0-9]+$'' then substring(task_row.priority from 2)::numeric end nulls last, task_row.due_at nulls last, task_row.created_at desc, task_row.id');
 updated_definition:=replace(updated_definition,
 'order by due_at nulls last, created_at desc',
 'order by case when priority ~ ''^P[0-9]+$'' then substring(priority from 2)::numeric end nulls last, due_at nulls last, created_at desc, id');
 if updated_definition=definition then raise exception 'Expected task sort missing'; end if;
 execute updated_definition;
end;
$$;
