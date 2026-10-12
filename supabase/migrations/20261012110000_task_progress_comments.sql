-- Append task comments and transitions without rewriting imported notes.
alter table public.task_events drop constraint task_events_event_type_check;
alter table public.task_events add constraint task_events_event_type_check check (event_type in ('created','accepted','postponed','started','completed','blocked','cancelled','reopened','corrected','commented'));
alter table public.task_events add column previous_state text, add column new_state text;
alter table public.task_events add constraint task_events_state_transition_check check (
  (previous_state is null or previous_state in ('0-Backlog','1-En curso','2-Completada','3-Bloqueada','4-Cancelada')) and
  (new_state is null or new_state in ('0-Backlog','1-En curso','2-Completada','3-Bloqueada','4-Cancelada')));

create function public.read_back_task_update(p_operation_key text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_owner uuid := private.require_call_report_owner(); v_receipt public.operation_receipts%rowtype; v_task uuid; v_event uuid;
begin
  select * into v_receipt from public.operation_receipts where owner_id=v_owner and operation_key=p_operation_key and operation_type='update_task_progress';
  if not found then raise exception 'task update unavailable' using errcode='P0002'; end if;
  select (x->>'id')::uuid into v_task from jsonb_array_elements(v_receipt.result_record_ids) x where x->>'type'='task';
  select (x->>'id')::uuid into v_event from jsonb_array_elements(v_receipt.result_record_ids) x where x->>'type'='task_event';
  return jsonb_build_object('saved',true,'task',(select to_jsonb(t)-'owner_id' from public.tasks t where owner_id=v_owner and id=v_task),'event',(select to_jsonb(e)-'owner_id' from public.task_events e where owner_id=v_owner and id=v_event));
end; $$;

create function public.update_task_progress(p_task_id uuid,p_state text,p_comment text,p_expected_lock_version bigint,p_operation_key text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_owner uuid := private.require_call_report_owner(); v_task public.tasks%rowtype; v_event uuid; v_type text; v_hash text; v_receipt public.operation_receipts%rowtype; v_now timestamptz := now(); v_comment text := nullif(btrim(p_comment),'');
begin
  if p_state is null or p_state not in ('0-Backlog','1-En curso','2-Completada','3-Bloqueada','4-Cancelada') or length(coalesce(p_comment,''))>2000 or p_expected_lock_version is null or p_expected_lock_version<1 or nullif(btrim(p_operation_key),'') is null then
    raise exception 'invalid task update' using errcode='22023';
  end if;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('id',p_task_id,'state',p_state,'comment',v_comment,'version',p_expected_lock_version)::text,'UTF8'),'sha256'),'hex');
  -- Serialize same-operation retries even when the row version has advanced.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_owner::text||p_operation_key,0));
  select * into v_receipt from public.operation_receipts where owner_id=v_owner and operation_key=p_operation_key;
  if found then
    if v_receipt.operation_type<>'update_task_progress' or v_receipt.request_sha256<>v_hash then raise exception 'operation key conflicts' using errcode='23505'; end if;
    return public.read_back_task_update(p_operation_key);
  end if;
  select * into v_task from public.tasks where owner_id=v_owner and id=p_task_id and authority_state='commitment' for update;
  if not found then raise exception 'task unavailable' using errcode='P0002'; end if;
  if v_task.lock_version<>p_expected_lock_version then raise exception 'task changed; refresh before editing' using errcode='40001'; end if;
  if p_state=v_task.state and v_comment is null then raise exception 'state change or comment required' using errcode='22023'; end if;
  v_type:=case when p_state=v_task.state then 'commented' when p_state='2-Completada' then 'completed' when p_state='4-Cancelada' then 'cancelled' when p_state='3-Bloqueada' then 'blocked' when p_state='1-En curso' then 'started' else 'reopened' end;
  update public.tasks set state=p_state, completed_at=case when p_state='2-Completada' then coalesce(v_task.completed_at,v_now) else null end where owner_id=v_owner and id=p_task_id;
  insert into public.task_events(owner_id,task_id,event_type,occurred_at,note,operation_key,previous_state,new_state) values(v_owner,p_task_id,v_type,v_now,v_comment,p_operation_key||':event',v_task.state,p_state) returning id into v_event;
  insert into public.operation_receipts(owner_id,operation_key,operation_type,request_sha256,result_record_ids) values(v_owner,p_operation_key,'update_task_progress',v_hash,jsonb_build_array(jsonb_build_object('type','task','id',p_task_id),jsonb_build_object('type','task_event','id',v_event)));
  return public.read_back_task_update(p_operation_key);
end; $$;
revoke all on function public.update_task_progress(uuid,text,text,bigint,text), public.read_back_task_update(text) from public,anon;
grant execute on function public.update_task_progress(uuid,text,text,bigint,text), public.read_back_task_update(text) to authenticated;

-- Read only the selected record and its explicit owner-scoped context.
create or replace function public.get_crm_record_context(p_kind text, p_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path = ''
as $$
declare
  v_owner uuid := (select auth.uid());
  v_result jsonb;
  v_company uuid;
  v_opportunity uuid;
  v_application uuid;
  v_interaction uuid;
  v_contacts jsonb;
  v_events jsonb;
begin
  if v_owner is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_kind not in ('task', 'interaction', 'opportunity', 'application') or p_kind is null then
    raise exception 'Unsupported record kind' using errcode = '22023';
  end if;
  if p_kind = 'task' then
    select jsonb_build_object('title',t.title,'notes',t.notes,'state',t.state,'priority',t.priority,
      'due_at',t.due_at,'completed_at',t.completed_at,'task_type',t.task_type),
      t.context_company_id,t.context_opportunity_id,t.context_application_id,t.source_interaction_id
    into v_result,v_company,v_opportunity,v_application,v_interaction
    from public.tasks t where t.owner_id=v_owner and t.id=p_id;
    select coalesce(jsonb_agg(x.item order by x.occurred_at,x.id),'[]'::jsonb) into v_events
    from (select e.id,e.occurred_at,jsonb_build_object('event_type',e.event_type,'occurred_at',e.occurred_at,'note',e.note,'previous_state',e.previous_state,'new_state',e.new_state) item
      from public.task_events e where e.owner_id=v_owner and e.task_id=p_id
      order by e.occurred_at desc,e.id desc limit 20) x;
  elsif p_kind = 'interaction' then
    select jsonb_build_object('title',i.title,'summary',i.summary,'insight',i.insight,'result',i.result,
      'next_step',i.next_step,'follow_up_at',i.follow_up_at,'interaction_type',i.interaction_type,'occurred_at',i.occurred_at),
      i.context_company_id,i.context_opportunity_id,i.context_application_id,i.id
    into v_result,v_company,v_opportunity,v_application,v_interaction
    from public.interactions i where i.owner_id=v_owner and i.id=p_id;
  elsif p_kind = 'opportunity' then
    select jsonb_build_object('title',o.title,'notes',o.notes,'next_step',o.next_step,'next_step_at',o.next_step_at,
      'target_role',o.target_role,'role_fit',o.role_fit,'primary_risk',o.primary_risk,'status',o.status,
      'priority',o.priority,'location',o.location,'work_mode',o.work_mode),o.company_id,o.id
    into v_result,v_company,v_opportunity
    from public.opportunities o where o.owner_id=v_owner and o.id=p_id;
  else
    select jsonb_build_object('title',coalesce(j.title,o.title,c.name),'submission_evidence',a.submission_evidence,
      'submitted_at',a.submitted_at,'channel',a.channel,'missing_snapshot_reason',a.missing_snapshot_reason,
      'missing_material_reason',a.missing_material_reason),a.company_id,a.opportunity_id,a.id
    into v_result,v_company,v_opportunity,v_application
    from public.applications a
    join public.companies c on c.owner_id=v_owner and c.id=a.company_id
    left join public.job_postings j on j.owner_id=v_owner and j.id=a.job_posting_id
    left join public.opportunities o on o.owner_id=v_owner and o.id=a.opportunity_id
    where a.owner_id=v_owner and a.id=p_id;
    select coalesce(jsonb_agg(x.item order by x.occurred_at,x.id),'[]'::jsonb) into v_events
    from (select e.id,e.occurred_at,jsonb_build_object('event_type',e.event_type,'occurred_at',e.occurred_at,'note',e.note) item
      from public.application_events e where e.owner_id=v_owner and e.application_id=p_id
      order by e.occurred_at desc,e.id desc limit 20) x;
  end if;
  if v_result is null then return null; end if;
  if p_kind='task' and v_interaction is not null then
    select v_result || jsonb_build_object('source_interaction_title',i.title,'source_summary',i.summary,
      'source_result',i.result,'source_next_step',i.next_step,'source_occurred_at',i.occurred_at),
      coalesce(v_company,i.context_company_id),coalesce(v_opportunity,i.context_opportunity_id),coalesce(v_application,i.context_application_id)
    into v_result,v_company,v_opportunity,v_application
    from public.interactions i where i.owner_id=v_owner and i.id=v_interaction;
  end if;
  if v_application is not null then
    select coalesce(v_company,a.company_id),coalesce(v_opportunity,a.opportunity_id)
    into v_company,v_opportunity from public.applications a where a.owner_id=v_owner and a.id=v_application;
  end if;
  if v_opportunity is not null then
    select coalesce(v_company,o.company_id),v_result || jsonb_build_object('opportunity_title',o.title)
    into v_company,v_result from public.opportunities o where o.owner_id=v_owner and o.id=v_opportunity;
  end if;
  if v_company is not null then
    select v_result || jsonb_build_object('company_name',c.name) into v_result
    from public.companies c where c.owner_id=v_owner and c.id=v_company;
  end if;
  select coalesce(jsonb_agg(x.item order by x.name),'[]'::jsonb) into v_contacts
  from (select distinct c.name,jsonb_build_object('name',c.name,'job_title',c.job_title) item
    from public.contacts c where c.owner_id=v_owner and (
      exists(select 1 from public.task_contacts tc where p_kind='task' and tc.owner_id=v_owner and tc.task_id=p_id and tc.contact_id=c.id)
      or exists(select 1 from public.interaction_contacts ic where ic.owner_id=v_owner and ic.interaction_id=v_interaction and ic.contact_id=c.id)
      or exists(select 1 from public.opportunity_contacts oc where oc.owner_id=v_owner and oc.opportunity_id=v_opportunity and oc.contact_id=c.id))
    order by c.name limit 10) x;
  return jsonb_strip_nulls(v_result || jsonb_build_object('contacts',v_contacts,'events',coalesce(v_events,'[]'::jsonb)));
end;
$$;
revoke all on function public.get_crm_record_context(text,uuid) from public,anon;
grant execute on function public.get_crm_record_context(text,uuid) to authenticated;
comment on function public.get_crm_record_context(text,uuid) is
  'Selected CRM context only; invoker RLS, explicit owner predicates, four allowed kinds, ten linked contacts and twenty recent events.';
