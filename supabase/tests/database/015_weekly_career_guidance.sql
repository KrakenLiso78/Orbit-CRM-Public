-- Traceability: Personal CRM US12, FR-052–057 and SC-019–021.
-- All records and mutations are synthetic and rolled back.
begin;
create temporary table weekly_guidance_results(name text,passed boolean);
grant select,insert on weekly_guidance_results to authenticated;

do $$
declare
  o uuid:='91000000-0000-0000-0000-000000000015';
  other_owner uuid:='91000000-0000-0000-0000-000000000016';
  c uuid:='92000000-0000-0000-0000-000000000015';
  contact uuid:='93000000-0000-0000-0000-000000000015';
  opp uuid:='94000000-0000-0000-0000-000000000015';
  task uuid:='95000000-0000-0000-0000-000000000015';
  i1 uuid:='96000000-0000-0000-0000-000000000015';
  i2 uuid:='96000000-0000-0000-0000-000000000016';
  i3 uuid:='96000000-0000-0000-0000-000000000017';
  cutoff timestamptz:=date_trunc('second',now());
  payload jsonb;
  payload2 jsonb;
  result jsonb;
  opp_version bigint;
  task_version bigint;
  before_contacts integer;
  before_applications integer;
  before_application_events integer;
begin
  insert into auth.users(id,aud,role) values(o,'authenticated','authenticated'),(other_owner,'authenticated','authenticated');
  insert into public.crm_owner_profiles(owner_id) values(o),(other_owner);
  insert into public.companies(id,owner_id,name) values(c,o,'Synthetic Weekly Guidance Company');
  insert into public.contacts(id,owner_id,name,priority,last_contact_at) values(contact,o,'Synthetic Weekly Contact','P0',cutoff-interval '14 days');
  insert into public.opportunities(id,owner_id,company_id,title,status,priority,next_step,lock_version) values(opp,o,c,'Synthetic Product AI Role','Open','P1','Review evidence',1);
  insert into public.tasks(id,owner_id,title,state,authority_state,priority,due_at,lock_version) values(task,o,'Verify synthetic application context','0-Backlog','commitment','P1',cutoff+interval '4 days',1);
  insert into public.interactions(id,owner_id,title,occurred_at,summary,context_opportunity_id) values
    (i1,o,'Recent synthetic signal',cutoff-interval '2 days','Confirmed interest',opp),
    (i2,o,'Older synthetic contact',cutoff-interval '14 days','No later reply recorded',null),
    (i3,o,'Pending synthetic verification',cutoff-interval '1 day','Application state not inferred',null);
  insert into public.interaction_contacts(owner_id,interaction_id,contact_id) values(o,i2,contact);

  perform set_config('request.jwt.claim.sub',o::text,true);
  execute 'set local role authenticated';
  select lock_version into opp_version from public.opportunities where id=opp;
  select lock_version into task_version from public.tasks where id=task;
  select count(*) into before_contacts from public.contacts;
  select count(*) into before_applications from public.applications;
  select count(*) into before_application_events from public.application_events;

  payload:=jsonb_build_object(
    'information_cutoff',cutoff,'summary_es','Plan sintético de tres acciones.','evidence_limitations',jsonb_build_array('Una señal es antigua.'),
    'actions',jsonb_build_array(
      jsonb_build_object('rank',1,'action_key','opp-insist','action_identity','opp:insist:follow-up','classification','insist','target_type','opportunity','target_id',opp,
        'evidence_state','confirmed','evidence_refs',jsonb_build_array(jsonb_build_object('record_type','interaction','record_id',i1,'observed_at',cutoff-interval '2 days')),
        'reason_es','Hay una señal confirmada reciente.','next_step_es','Preparar un seguimiento concreto.','suggested_due_at',cutoff+interval '2 days',
        'opportunity_effect',jsonb_build_object('opportunity_id',opp,'expected_lock_version',opp_version,'status','En curso','priority','P0','next_step','Preparar seguimiento','next_step_at',cutoff+interval '2 days'),
        'task_effect',jsonb_build_object('mode','create','action_identity','opp:insist:follow-up','title','Preparar seguimiento sintético','priority','P0','due_at',cutoff+interval '2 days','notes','Synthetic weekly fixture')),
      jsonb_build_object('rank',2,'action_key','contact-wait','action_identity','contact:wait:verify','classification','wait','target_type','contact','target_id',contact,
        'evidence_state','old','evidence_refs',jsonb_build_array(jsonb_build_object('record_type','interaction','record_id',i2,'observed_at',cutoff-interval '14 days')),
        'reason_es','La última señal es antigua y no hay novedad confirmada.','next_step_es','Esperar y verificar antes de insistir.','suggested_due_at',cutoff+interval '7 days',
        'task_effect',jsonb_build_object('mode','create','action_identity','contact:wait:verify','title','Verificar novedad sintética','priority','P1','due_at',cutoff+interval '7 days','notes','Synthetic weekly fixture')),
      jsonb_build_object('rank',3,'action_key','task-verify','action_identity','task:verify:context','classification','verify','target_type','task','target_id',task,
        'evidence_state','pending_verification','evidence_refs',jsonb_build_array(jsonb_build_object('record_type','interaction','record_id',i3,'observed_at',cutoff-interval '1 day')),
        'reason_es','El estado necesita verificación.','next_step_es','Revisar la evidencia antes de cambiar el estado.','suggested_due_at',cutoff+interval '3 days',
        'task_effect',jsonb_build_object('mode','update','action_identity','task:verify:context','task_id',task,'expected_lock_version',task_version,'priority','P0','due_at',cutoff+interval '3 days'))
    ));

  result:=public.record_weekly_career_guidance(payload,'weekly-guidance-synthetic-1');
  insert into weekly_guidance_results values
    ('Exactly three ranked actions saved',jsonb_array_length(result->'actions')=3 and (result#>>'{actions,0,rank}')::int=1 and (result#>>'{actions,2,rank}')::int=3),
    ('Opportunity plan updated',result#>>'{opportunities,0,status}'='En curso' and result#>>'{opportunities,0,priority}'='P0'),
    ('Two tasks created and one updated',jsonb_array_length(result->'tasks')=3 and jsonb_array_length(result->'task_events')=3),
    ('Separate readback matches',result=public.read_back_weekly_career_guidance('weekly-guidance-synthetic-1')),
    ('Exact retry returns original',result=public.record_weekly_career_guidance(payload,'weekly-guidance-synthetic-1')),
    ('Forbidden records unchanged',(select count(*) from public.contacts)=before_contacts and (select count(*) from public.applications)=before_applications and (select count(*) from public.application_events)=before_application_events);

  begin perform public.record_weekly_career_guidance(jsonb_set(payload,'{summary_es}','"Changed"'),'weekly-guidance-synthetic-1'); raise exception 'changed replay saved';
  exception when unique_violation then insert into weekly_guidance_results values('Changed replay rejected',true); end;

  select lock_version into opp_version from public.opportunities where id=opp;
  select lock_version into task_version from public.tasks where id=task;
  payload2:=jsonb_set(jsonb_set(payload,'{actions,0,opportunity_effect,expected_lock_version}',to_jsonb(opp_version)),'{actions,2,task_effect,expected_lock_version}',to_jsonb(task_version));
  result:=public.record_weekly_career_guidance(payload2,'weekly-guidance-synthetic-2');
  insert into weekly_guidance_results values
    ('Equivalent open commitments reused',jsonb_array_length(result->'task_events')=1 and (select count(*)=3 from public.tasks where owner_id=o));

  select lock_version into opp_version from public.opportunities where id=opp;
  select lock_version into task_version from public.tasks where id=task;
  payload2:=jsonb_set(jsonb_set(payload2,'{actions,0,opportunity_effect,expected_lock_version}',to_jsonb(opp_version)),'{actions,2,task_effect,expected_lock_version}',to_jsonb(task_version));
  begin perform public.record_weekly_career_guidance(jsonb_set(payload2,'{actions,0,classification}','"close_front"'), 'weekly-guidance-bad-close'); raise exception 'unsupported closure saved';
  exception when invalid_parameter_value then insert into weekly_guidance_results values('Unsupported closure rejected atomically',not exists(select 1 from public.weekly_career_reviews where owner_id=o and summary_es='Plan sintético de tres acciones.' and id not in (select review_id from public.weekly_career_actions where action_key='opp-insist'))); end;

  begin perform public.record_weekly_career_guidance(jsonb_set(payload2,'{actions}',jsonb_build_array(payload2#>'{actions,0}',payload2#>'{actions,1}')),'weekly-guidance-two'); raise exception 'two actions saved';
  exception when invalid_parameter_value then insert into weekly_guidance_results values('Invalid action count rejected',true); end;

  execute 'reset role';
  perform set_config('request.jwt.claim.sub',other_owner::text,true);
  execute 'set local role authenticated';
  begin perform public.record_weekly_career_guidance(payload,'weekly-guidance-foreign'); raise exception 'foreign guidance saved';
  exception when no_data_found or insufficient_privilege or invalid_parameter_value then insert into weekly_guidance_results values('Foreign owner targets denied',not exists(select 1 from public.weekly_career_reviews where owner_id=other_owner)); end;
  begin perform public.read_back_weekly_career_guidance('weekly-guidance-synthetic-1'); raise exception 'foreign readback exposed';
  exception when no_data_found then insert into weekly_guidance_results values('Foreign owner readback denied',true); end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  insert into weekly_guidance_results values
    ('Anonymous functions denied',not has_function_privilege('anon','public.get_weekly_career_guidance_context(integer)','execute') and not has_function_privilege('anon','public.record_weekly_career_guidance(jsonb,text)','execute') and not has_function_privilege('anon','public.read_back_weekly_career_guidance(text)','execute'));
end;
$$;

do $$ begin if exists(select 1 from weekly_guidance_results where passed is distinct from true) then raise exception 'weekly career guidance regression failed'; end if; end $$;
select * from weekly_guidance_results order by name;
rollback;
