-- Traceability: Personal CRM US11, FR-050–051 and SC-017–018.
-- All task edits in this regression are synthetic and rolled back.
begin;
create temporary table task_edit_results(name text,passed boolean);
grant select,insert on task_edit_results to authenticated;
do $$
declare o uuid:='81000000-0000-0000-0000-000000000014'; other_owner uuid:='81000000-0000-0000-0000-000000000015'; t uuid:='85000000-0000-0000-0000-000000000014'; v bigint; r jsonb;
begin
 insert into auth.users(id,aud,role) values(o,'authenticated','authenticated'),(other_owner,'authenticated','authenticated');
 insert into public.crm_owner_profiles(owner_id) values(o),(other_owner);
 insert into public.tasks(id,owner_id,title,notes,state) values(t,o,'Synthetic task editor','Immutable earlier note','0-Backlog');
 perform set_config('request.jwt.claim.sub',o::text,true);
 execute 'set local role authenticated';
 select lock_version into v from public.tasks where id=t;
 begin perform public.update_task_progress(t,'0-Backlog',' ',v,'no-op'); raise exception 'no-op saved'; exception when invalid_parameter_value then insert into task_edit_results values('Empty unchanged edit rejected',true); end;
 begin perform public.update_task_progress(t,'unexpected','Comment',v,'invalid'); raise exception 'invalid state saved'; exception when invalid_parameter_value then insert into task_edit_results values('Unknown state rejected',true); end;
 begin perform public.update_task_progress(t,'0-Backlog',repeat('a',2001),v,'long'); raise exception 'long comment saved'; exception when invalid_parameter_value then insert into task_edit_results values('Long comment rejected',true); end;
 r:=public.update_task_progress(t,'0-Backlog','Comment only',v,'synthetic-comment');
 insert into task_edit_results values
 ('Comment-only event saved',r #>> '{event,event_type}'='commented' and r #>> '{event,note}'='Comment only'),
 ('Original notes preserved',r #>> '{task,notes}'='Immutable earlier note'),
 ('Exact retry returns authoritative event',r=public.update_task_progress(t,'0-Backlog','Comment only',v,'synthetic-comment')),
 ('Separate readback matches result',r=public.read_back_task_update('synthetic-comment'));
 begin perform public.update_task_progress(t,'1-En curso','Different',v,'synthetic-comment'); raise exception 'key reused'; exception when unique_violation then insert into task_edit_results values('Conflicting replay rejected',true); end;
 begin perform public.update_task_progress(t,'1-En curso','Stale',v,'synthetic-stale'); raise exception 'stale saved'; exception when serialization_failure then insert into task_edit_results values('Stale version rejected',true); end;
 select lock_version into v from public.tasks where id=t;
 r:=public.update_task_progress(t,'1-En curso','Started work',v,'synthetic-start');
 insert into task_edit_results values('Transition states preserved',r #>> '{event,previous_state}'='0-Backlog' and r #>> '{event,new_state}'='1-En curso');
 select lock_version into v from public.tasks where id=t;
 r:=public.update_task_progress(t,'3-Bloqueada','Waiting',v,'synthetic-block');
 insert into task_edit_results values('Blocked state and event saved',r #>> '{task,state}'='3-Bloqueada' and r #>> '{event,event_type}'='blocked');
 select lock_version into v from public.tasks where id=t;
 r:=public.update_task_progress(t,'2-Completada','Finished',v,'synthetic-complete');
 insert into task_edit_results values
 ('Completion timestamp saved',r #>> '{task,completed_at}' is not null),
 ('Completed task leaves upcoming lane',jsonb_array_length(public.get_dashboard_snapshot()->'due_tasks')=0),
 ('Completed task appears in completed history',jsonb_array_length(public.get_dashboard_snapshot()->'recent_completed_tasks')=1);
 select lock_version into v from public.tasks where id=t;
 r:=public.update_task_progress(t,'0-Backlog','Reopened',v,'synthetic-reopen');
 insert into task_edit_results values('Reopening clears completion timestamp',r #>> '{task,completed_at}' is null and r #>> '{event,event_type}'='reopened');
 select lock_version into v from public.tasks where id=t;
 r:=public.update_task_progress(t,'4-Cancelada','Cancelled',v,'synthetic-cancel');
 insert into task_edit_results values
 ('Cancellation removes task from open KPI',(public.get_dashboard_snapshot() #>> '{counts,open_tasks}')::int=0),
 ('One event per successful action',(select count(*)=6 from public.task_events where task_id=t)),
 ('Notes remain unchanged after all transitions',(select notes='Immutable earlier note' from public.tasks where id=t)),
 ('Context includes transition and comment history',exists(select 1 from jsonb_array_elements(public.get_crm_record_context('task',t)->'events') e where e->>'note'='Started work' and e->>'previous_state'='0-Backlog' and e->>'new_state'='1-En curso'));
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',other_owner::text,true);
 execute 'set local role authenticated';
 begin perform public.update_task_progress(t,'0-Backlog','Foreign',1,'foreign'); raise exception 'foreign saved'; exception when no_data_found then insert into task_edit_results values('Wrong owner write denied',true); end;
 begin perform public.read_back_task_update('synthetic-comment'); raise exception 'foreign read'; exception when no_data_found then insert into task_edit_results values('Wrong owner readback denied',true); end;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.update_task_progress(t,'0-Backlog','No identity',1,'expired'); raise exception 'unauth saved'; exception when insufficient_privilege then insert into task_edit_results values('Missing identity denied',true); end;
 insert into task_edit_results values('Anonymous RPC denied',not has_function_privilege('anon','public.update_task_progress(uuid,text,text,bigint,text)','execute'));
end; $$;
do $$ begin if exists(select 1 from task_edit_results where passed is distinct from true) then raise exception 'task editor regression failed'; end if; end; $$;
select * from task_edit_results order by name;
rollback;
