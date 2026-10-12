begin;
set local statement_timeout='15s';
do $$
declare
  own uuid:=gen_random_uuid(); other_owner uuid:=gen_random_uuid(); company uuid:=gen_random_uuid();
  person uuid:=gen_random_uuid(); interaction uuid:=gen_random_uuid(); task uuid:=gen_random_uuid();
  opportunity uuid:=gen_random_uuid(); application uuid:=gen_random_uuid(); result jsonb;
begin
  insert into auth.users(id,aud,role) values(own,'authenticated','authenticated'),(other_owner,'authenticated','authenticated');
  insert into public.crm_owner_profiles(owner_id) values(own),(other_owner);
  insert into public.companies(id,owner_id,name) values(company,own,'Synthetic context company');
  insert into public.contacts(id,owner_id,name,job_title) values(person,own,'Synthetic context contact','Synthetic role');
  insert into public.interactions(id,owner_id,title,occurred_at,summary,result,next_step,context_company_id)
    values(interaction,own,'Synthetic context conversation',now(),'Narrative context','Recorded result','Explicit next action',company);
  insert into public.interaction_contacts(owner_id,interaction_id,contact_id) values(own,interaction,person);
  insert into public.tasks(id,owner_id,title,notes,source_interaction_id)
    values(task,own,'Synthetic context task','Detailed task notes',interaction);
  insert into public.opportunities(id,owner_id,company_id,title,notes,next_step)
    values(opportunity,own,company,'Synthetic context opportunity','Opportunity evidence','Next opportunity action');
  insert into public.opportunity_contacts(owner_id,opportunity_id,contact_id,role) values(own,opportunity,person,'recruiter');
  insert into public.applications(id,owner_id,company_id,opportunity_id,submitted_at,channel,submission_evidence)
    values(application,own,company,opportunity,now(),'direct','Submission evidence');
  insert into public.task_events(owner_id,task_id,event_type,occurred_at,note,operation_key)
    select own,task,'created',now()-n*interval '1 minute','Synthetic event '||n,'context-test-'||n from generate_series(1,22) n;
  insert into public.application_events(owner_id,application_id,event_type,occurred_at,note,operation_key)
    values(own,application,'submitted',now(),'Confirmed submission','context-application-test');
  perform set_config('request.jwt.claim.sub',own::text,true);
  execute 'set local role authenticated';
  result:=public.get_crm_record_context('task',task);
  if result->>'notes'<>'Detailed task notes' or result->>'source_summary'<>'Narrative context'
    or result->>'company_name'<>'Synthetic context company' or result#>>'{contacts,0,name}'<>'Synthetic context contact'
    or jsonb_array_length(result->'events')<>20 then raise exception 'Task context or bounds failed'; end if;
  if result#>>'{events,0,note}'<>'Synthetic event 20' or result#>>'{events,19,note}'<>'Synthetic event 1' then raise exception 'History order failed'; end if;
  result:=public.get_crm_record_context('interaction',interaction);
  if result->>'summary'<>'Narrative context' or result->>'next_step'<>'Explicit next action' then raise exception 'Interaction context failed'; end if;
  result:=public.get_crm_record_context('opportunity',opportunity);
  if result->>'notes'<>'Opportunity evidence' or jsonb_array_length(result->'contacts')<>1 then raise exception 'Opportunity context failed'; end if;
  result:=public.get_crm_record_context('application',application);
  if result->>'submission_evidence'<>'Submission evidence' or result#>>'{events,0,note}'<>'Confirmed submission' then raise exception 'Application context failed'; end if;
  if public.get_crm_record_context('task',gen_random_uuid()) is not null then raise exception 'Unknown ID returned data'; end if;
  begin
    perform public.get_crm_record_context('arbitrary_table',task);
    raise exception 'Invalid kind accepted';
  exception when invalid_parameter_value then null; end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',other_owner::text,true);
  execute 'set local role authenticated';
  if public.get_crm_record_context('task',task) is not null
    or public.get_crm_record_context('interaction',interaction) is not null
    or public.get_crm_record_context('opportunity',opportunity) is not null
    or public.get_crm_record_context('application',application) is not null then raise exception 'Foreign context disclosed'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  execute 'set local role anon';
  begin
    perform public.get_crm_record_context('task',task);
    raise exception 'Anonymous context allowed';
  exception when insufficient_privilege then null; end;
  execute 'reset role';
  raise notice 'CRM selected context regression passed; fixtures rolled back';
end;
$$;
rollback;
