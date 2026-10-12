-- Owner-scoped weekly Product/AI career guidance with exactly three actions.
-- Created manually because the Supabase CLI is unavailable in this checkout.

create table public.weekly_career_reviews (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  information_cutoff timestamptz not null,
  summary_es text not null check (btrim(summary_es) <> '' and length(summary_es) <= 4000),
  evidence_limitations jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_limitations) = 'array'),
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id)
);

create table public.weekly_career_actions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  review_id uuid not null,
  rank smallint not null check (rank between 1 and 3),
  action_key text not null check (btrim(action_key) <> '' and length(action_key) <= 200),
  action_identity text not null check (btrim(action_identity) <> '' and length(action_identity) <= 300),
  classification text not null check (classification in ('insist','wait','change_focus','close_front','verify')),
  target_type text not null check (target_type in ('contact','company','opportunity','application','task')),
  target_id uuid not null,
  evidence_state text not null check (evidence_state in ('confirmed','old','pending_verification','conflicting')),
  evidence_refs jsonb not null check (jsonb_typeof(evidence_refs) = 'array'),
  reason_es text not null check (btrim(reason_es) <> '' and length(reason_es) <= 2000),
  next_step_es text not null check (btrim(next_step_es) <> '' and length(next_step_es) <= 2000),
  suggested_due_at timestamptz,
  opportunity_id uuid,
  opportunity_effect jsonb,
  task_id uuid,
  task_event_id uuid,
  task_effect_mode text not null check (task_effect_mode in ('create','update','reuse','none')),
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, review_id, rank),
  unique (owner_id, review_id, action_key),
  unique (owner_id, review_id, target_type, target_id),
  foreign key (owner_id, review_id) references public.weekly_career_reviews(owner_id, id) on delete cascade,
  foreign key (owner_id, opportunity_id) references public.opportunities(owner_id, id) on delete restrict,
  foreign key (owner_id, task_id) references public.tasks(owner_id, id) on delete restrict,
  foreign key (owner_id, task_event_id) references public.task_events(owner_id, id) on delete restrict,
  check (opportunity_effect is null or jsonb_typeof(opportunity_effect) = 'object')
);

create index weekly_career_reviews_owner_created_idx
  on public.weekly_career_reviews (owner_id, created_at desc);
create index weekly_career_actions_review_idx
  on public.weekly_career_actions (owner_id, review_id, rank);
create index weekly_career_actions_opportunity_idx
  on public.weekly_career_actions (owner_id, opportunity_id) where opportunity_id is not null;
create index weekly_career_actions_task_idx
  on public.weekly_career_actions (owner_id, task_id) where task_id is not null;
create index weekly_career_actions_identity_idx
  on public.weekly_career_actions (owner_id, action_identity, created_at desc);

alter table public.weekly_career_reviews enable row level security;
alter table public.weekly_career_reviews force row level security;
alter table public.weekly_career_actions enable row level security;
alter table public.weekly_career_actions force row level security;

create policy weekly_career_reviews_owner_select on public.weekly_career_reviews
  for select to authenticated using ((select auth.uid()) = owner_id);
create policy weekly_career_actions_owner_select on public.weekly_career_actions
  for select to authenticated using ((select auth.uid()) = owner_id);

revoke all on public.weekly_career_reviews, public.weekly_career_actions from public, anon, authenticated;
grant select on public.weekly_career_reviews, public.weekly_career_actions to authenticated;

create or replace function private.weekly_guidance_record_exists(
  p_owner uuid,
  p_type text,
  p_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return case p_type
    when 'contact' then exists(select 1 from public.contacts where owner_id=p_owner and id=p_id)
    when 'company' then exists(select 1 from public.companies where owner_id=p_owner and id=p_id)
    when 'opportunity' then exists(select 1 from public.opportunities where owner_id=p_owner and id=p_id)
    when 'application' then exists(select 1 from public.applications where owner_id=p_owner and id=p_id)
    when 'task' then exists(select 1 from public.tasks where owner_id=p_owner and id=p_id)
    when 'interaction' then exists(select 1 from public.interactions where owner_id=p_owner and id=p_id)
    else false
  end;
end;
$$;
revoke all on function private.weekly_guidance_record_exists(uuid,text,uuid) from public, anon, authenticated;

create or replace function public.get_weekly_career_guidance_context(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_owner uuid := (select auth.uid());
  v_limit integer := greatest(1, least(coalesce(p_limit,50),100));
begin
  if v_owner is null then raise exception 'Authentication required' using errcode='42501'; end if;
  return jsonb_build_object(
    'information_cutoff', timezone('utc',now()),
    'profile', coalesce((select jsonb_build_object('id',p.id,'version_label',p.version_label,'profile_data',p.profile_data,'approved_at',p.approved_at)
      from public.candidate_profile_versions p where p.owner_id=v_owner order by p.approved_at desc nulls last,p.created_at desc limit 1),'null'::jsonb),
    'contacts', coalesce((select jsonb_agg(to_jsonb(x) order by x.last_contact_at desc nulls last,x.updated_at desc)
      from (select c.id,c.name,c.job_title,c.location,c.relationship_strength,c.relationship_state,c.priority,
        c.last_contact_at,c.next_follow_up_at,c.context_notes,c.updated_at,c.lock_version
        from public.contacts c where c.owner_id=v_owner and c.archived_at is null
        order by c.last_contact_at desc nulls last,c.updated_at desc limit v_limit) x),'[]'::jsonb),
    'interactions', coalesce((select jsonb_agg(to_jsonb(x) order by x.occurred_at desc)
      from (select i.id,i.title,i.interaction_type,i.occurred_at,i.summary,i.result,i.next_step,i.follow_up_at,
        i.context_company_id,i.context_opportunity_id,i.context_application_id,i.updated_at,i.lock_version
        from public.interactions i where i.owner_id=v_owner order by i.occurred_at desc limit v_limit) x),'[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(to_jsonb(x) order by x.due_at nulls last,x.updated_at desc)
      from (select t.id,t.title,t.task_type,t.state,t.authority_state,t.priority,t.due_at,t.notes,t.source_interaction_id,
        t.context_company_id,t.context_opportunity_id,t.context_application_id,t.updated_at,t.lock_version
        from public.tasks t where t.owner_id=v_owner and t.state not in ('2-Completada','4-Cancelada')
        order by t.due_at nulls last,t.updated_at desc limit v_limit) x),'[]'::jsonb),
    'opportunities', coalesce((select jsonb_agg(to_jsonb(x) order by x.next_step_at nulls last,x.updated_at desc)
      from (select o.id,o.company_id,o.title,o.status,o.priority,o.last_movement_at,o.next_step_at,o.next_step,
        o.target_role,o.role_fit,o.sector_fit,o.risk_level,o.primary_risk,o.location,o.work_mode,o.updated_at,o.lock_version
        from public.opportunities o where o.owner_id=v_owner and o.archived_at is null
        order by o.next_step_at nulls last,o.updated_at desc limit v_limit) x),'[]'::jsonb),
    'applications', coalesce((select jsonb_agg(to_jsonb(x) order by x.submitted_at desc)
      from (select a.id,a.company_id,a.opportunity_id,a.job_posting_id,a.submitted_at,a.channel,a.source_url,a.updated_at,a.lock_version,
        e.event_type latest_event_type,e.occurred_at latest_event_at,e.note latest_event_note
        from public.applications a
        left join lateral (select ae.event_type,ae.occurred_at,ae.note from public.application_events ae
          where ae.owner_id=a.owner_id and ae.application_id=a.id order by ae.occurred_at desc,ae.created_at desc,ae.id desc limit 1) e on true
        where a.owner_id=v_owner order by a.submitted_at desc limit v_limit) x),'[]'::jsonb)
  );
end;
$$;

create or replace function public.read_back_weekly_career_guidance(p_operation_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
  v_review uuid;
begin
  select * into v_receipt from public.operation_receipts
    where owner_id=v_owner and operation_key=p_operation_key and operation_type='weekly_career_guidance';
  if not found then raise exception 'weekly guidance unavailable' using errcode='P0002'; end if;
  select (x->>'id')::uuid into v_review from jsonb_array_elements(v_receipt.result_record_ids) x where x->>'type'='weekly_career_review' limit 1;
  return jsonb_build_object(
    'saved',true,
    'receipt',to_jsonb(v_receipt)-'owner_id',
    'review',(select to_jsonb(r)-'owner_id' from public.weekly_career_reviews r where r.owner_id=v_owner and r.id=v_review),
    'actions',coalesce((select jsonb_agg(to_jsonb(a)-'owner_id' order by a.rank) from public.weekly_career_actions a where a.owner_id=v_owner and a.review_id=v_review),'[]'::jsonb),
    'tasks',coalesce((select jsonb_agg(to_jsonb(t)-'owner_id' order by t.id) from public.tasks t where t.owner_id=v_owner and t.id in
      (select a.task_id from public.weekly_career_actions a where a.owner_id=v_owner and a.review_id=v_review and a.task_id is not null)),'[]'::jsonb),
    'task_events',coalesce((select jsonb_agg(to_jsonb(e)-'owner_id' order by e.id) from public.task_events e where e.owner_id=v_owner and e.id in
      (select a.task_event_id from public.weekly_career_actions a where a.owner_id=v_owner and a.review_id=v_review and a.task_event_id is not null)),'[]'::jsonb),
    'opportunities',coalesce((select jsonb_agg(to_jsonb(o)-'owner_id' order by o.id) from public.opportunities o where o.owner_id=v_owner and o.id in
      (select a.opportunity_id from public.weekly_career_actions a where a.owner_id=v_owner and a.review_id=v_review and a.opportunity_id is not null)),'[]'::jsonb)
  );
end;
$$;

create or replace function public.record_weekly_career_guidance(p_review jsonb,p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_hash text;
  v_receipt public.operation_receipts%rowtype;
  v_review_id uuid;
  v_cutoff timestamptz;
  v_action jsonb;
  v_evidence jsonb;
  v_opp_effect jsonb;
  v_task_effect jsonb;
  v_target_type text;
  v_target_id uuid;
  v_class text;
  v_evidence_state text;
  v_opp_id uuid;
  v_task_id uuid;
  v_event_id uuid;
  v_task_mode text;
  v_before jsonb;
  v_after jsonb;
  v_task public.tasks%rowtype;
  v_opp public.opportunities%rowtype;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if p_review is null or jsonb_typeof(p_review)<>'object' or nullif(btrim(p_operation_key),'') is null then
    raise exception 'invalid weekly guidance request' using errcode='22023';
  end if;
  if jsonb_typeof(p_review->'actions')<>'array' or jsonb_array_length(p_review->'actions')<>3 then
    raise exception 'weekly guidance requires exactly three actions' using errcode='22023';
  end if;
  if nullif(btrim(p_review->>'summary_es'),'') is null or length(p_review->>'summary_es')>4000
     or jsonb_typeof(coalesce(p_review->'evidence_limitations','[]'::jsonb))<>'array' then
    raise exception 'invalid weekly guidance summary' using errcode='22023';
  end if;
  begin v_cutoff := (p_review->>'information_cutoff')::timestamptz; exception when others then raise exception 'invalid information cutoff' using errcode='22023'; end;
  if v_cutoff is null or v_cutoff>now()+interval '5 minutes' then raise exception 'invalid information cutoff' using errcode='22023'; end if;
  if (select array_agg(distinct (a->>'rank')::int order by (a->>'rank')::int) from jsonb_array_elements(p_review->'actions') a) <> array[1,2,3]
     or (select count(distinct a->>'action_key') from jsonb_array_elements(p_review->'actions') a)<>3
     or (select count(distinct (a->>'target_type')||':'||(a->>'target_id')) from jsonb_array_elements(p_review->'actions') a)<>3 then
    raise exception 'weekly guidance ranks, keys, and targets must be unique' using errcode='22023';
  end if;

  v_hash:=encode(extensions.digest(convert_to(p_review::text,'UTF8'),'sha256'),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_owner::text||p_operation_key,0));
  select * into v_receipt from public.operation_receipts where owner_id=v_owner and operation_key=p_operation_key;
  if found then
    if v_receipt.operation_type<>'weekly_career_guidance' or v_receipt.request_sha256<>v_hash then raise exception 'operation key conflicts' using errcode='23505'; end if;
    return public.read_back_weekly_career_guidance(p_operation_key);
  end if;

  perform 1 from public.opportunities o where o.owner_id=v_owner and o.id in
    (select (a->'opportunity_effect'->>'opportunity_id')::uuid from jsonb_array_elements(p_review->'actions') a where a ? 'opportunity_effect' and jsonb_typeof(a->'opportunity_effect')='object')
    order by o.id for update;
  perform 1 from public.tasks t where t.owner_id=v_owner and t.id in
    (select (a->'task_effect'->>'task_id')::uuid from jsonb_array_elements(p_review->'actions') a where a ? 'task_effect' and a->'task_effect' ? 'task_id')
    order by t.id for update;

  insert into public.weekly_career_reviews(owner_id,information_cutoff,summary_es,evidence_limitations)
    values(v_owner,v_cutoff,btrim(p_review->>'summary_es'),coalesce(p_review->'evidence_limitations','[]'::jsonb)) returning id into v_review_id;
  v_result_ids:=jsonb_build_array(jsonb_build_object('type','weekly_career_review','id',v_review_id));

  for v_action in select value from jsonb_array_elements(p_review->'actions') order by (value->>'rank')::int loop
    begin v_target_id:=(v_action->>'target_id')::uuid; exception when others then raise exception 'invalid action target' using errcode='22023'; end;
    v_target_type:=v_action->>'target_type'; v_class:=v_action->>'classification'; v_evidence_state:=v_action->>'evidence_state';
    if v_class not in ('insist','wait','change_focus','close_front','verify')
       or v_evidence_state not in ('confirmed','old','pending_verification','conflicting')
       or v_target_type not in ('contact','company','opportunity','application','task')
       or not private.weekly_guidance_record_exists(v_owner,v_target_type,v_target_id)
       or nullif(btrim(v_action->>'action_key'),'') is null or length(v_action->>'action_key')>200
       or nullif(btrim(v_action->>'action_identity'),'') is null or length(v_action->>'action_identity')>300
       or nullif(btrim(v_action->>'reason_es'),'') is null or length(v_action->>'reason_es')>2000
       or nullif(btrim(v_action->>'next_step_es'),'') is null or length(v_action->>'next_step_es')>2000
       or jsonb_typeof(v_action->'evidence_refs')<>'array' then
      raise exception 'invalid weekly guidance action' using errcode='22023';
    end if;
    if v_evidence_state<>'confirmed' and v_class not in ('wait','verify') then raise exception 'uncertain evidence may only wait or verify' using errcode='22023'; end if;
    if (v_action->>'suggested_due_at') is not null and (v_action->>'suggested_due_at')::timestamptz<v_cutoff then raise exception 'action deadline precedes cutoff' using errcode='22023'; end if;
    for v_evidence in select value from jsonb_array_elements(v_action->'evidence_refs') loop
      if not private.weekly_guidance_record_exists(v_owner,v_evidence->>'record_type',(v_evidence->>'record_id')::uuid)
         or (v_evidence->>'observed_at')::timestamptz>v_cutoff then raise exception 'invalid action evidence' using errcode='22023'; end if;
    end loop;
    if v_class='close_front' and (v_target_type<>'opportunity' or v_evidence_state<>'confirmed' or jsonb_array_length(v_action->'evidence_refs')=0 or not (v_action?'opportunity_effect')) then
      raise exception 'close front requires confirmed opportunity evidence' using errcode='22023';
    end if;

    v_opp_id:=null; v_task_id:=null; v_event_id:=null; v_before:=null; v_after:=null;
    v_opp_effect:=v_action->'opportunity_effect';
    if v_opp_effect is not null and jsonb_typeof(v_opp_effect)<>'null' then
      if jsonb_typeof(v_opp_effect)<>'object' or exists(select 1 from jsonb_object_keys(v_opp_effect) k where k not in ('opportunity_id','expected_lock_version','status','priority','next_step','next_step_at')) then raise exception 'unsupported opportunity effect' using errcode='22023'; end if;
      v_opp_id:=(v_opp_effect->>'opportunity_id')::uuid;
      select * into v_opp from public.opportunities where owner_id=v_owner and id=v_opp_id and archived_at is null for update;
      if not found or v_opp.lock_version<>(v_opp_effect->>'expected_lock_version')::bigint then raise exception 'opportunity changed or unavailable' using errcode='PT409'; end if;
      if v_class='close_front' and lower(btrim(coalesce(v_opp_effect->>'status',''))) not in ('closed','cerrada','cerrado','cancelled','cancelada','cancelado') then raise exception 'close front requires terminal opportunity status' using errcode='22023'; end if;
      if v_class<>'close_front' and lower(btrim(coalesce(v_opp_effect->>'status',v_opp.status,''))) in ('closed','cerrada','cerrado','cancelled','cancelada','cancelado') then raise exception 'terminal opportunity status requires close front' using errcode='22023'; end if;
      if v_opp_effect ? 'priority' and coalesce(v_opp_effect->>'priority','') not in ('P0','P1','P2','P3') then raise exception 'invalid opportunity priority' using errcode='22023'; end if;
      if v_opp_effect ? 'next_step_at' and (v_opp_effect->>'next_step_at')::timestamptz<v_cutoff then raise exception 'opportunity next step precedes cutoff' using errcode='22023'; end if;
      v_before:=jsonb_build_object('status',v_opp.status,'priority',v_opp.priority,'next_step',v_opp.next_step,'next_step_at',v_opp.next_step_at,'lock_version',v_opp.lock_version);
      update public.opportunities set
        status=case when v_opp_effect?'status' then nullif(btrim(v_opp_effect->>'status'),'') else status end,
        priority=case when v_opp_effect?'priority' then nullif(v_opp_effect->>'priority','') else priority end,
        next_step=case when v_opp_effect?'next_step' then nullif(btrim(v_opp_effect->>'next_step'),'') else next_step end,
        next_step_at=case when v_opp_effect?'next_step_at' then nullif(v_opp_effect->>'next_step_at','')::timestamptz else next_step_at end,
        last_movement_at=timezone('utc',now())
        where owner_id=v_owner and id=v_opp_id returning jsonb_build_object('status',status,'priority',priority,'next_step',next_step,'next_step_at',next_step_at,'lock_version',lock_version) into v_after;
    end if;

    v_task_effect:=coalesce(v_action->'task_effect','{"mode":"none"}'::jsonb); v_task_mode:=coalesce(v_task_effect->>'mode','none');
    if v_task_mode not in ('create','update','reuse','none') or exists(select 1 from jsonb_object_keys(v_task_effect) k where k not in ('mode','action_identity','task_id','expected_lock_version','title','priority','due_at','notes')) then raise exception 'unsupported task effect' using errcode='22023'; end if;
    if v_task_mode='create' then
      select a.task_id into v_task_id from public.weekly_career_actions a join public.tasks t on t.owner_id=a.owner_id and t.id=a.task_id
        where a.owner_id=v_owner and a.action_identity=(v_action->>'action_identity') and t.authority_state='commitment' and t.state not in ('2-Completada','4-Cancelada')
        order by a.created_at desc limit 1 for update of t;
      if v_task_id is not null then v_task_mode:='reuse';
      else
        if nullif(btrim(v_task_effect->>'title'),'') is null or coalesce(v_task_effect->>'priority','') not in ('P0','P1','P2','P3') or (v_task_effect->>'due_at') is null or (v_task_effect->>'due_at')::timestamptz<v_cutoff then raise exception 'invalid created task' using errcode='22023'; end if;
        insert into public.tasks(owner_id,title,task_type,state,authority_state,priority,due_at,notes,context_company_id,context_opportunity_id,context_application_id)
          values(v_owner,btrim(v_task_effect->>'title'),'weekly_career_guidance','0-Backlog','commitment',v_task_effect->>'priority',(v_task_effect->>'due_at')::timestamptz,nullif(btrim(v_task_effect->>'notes'),''),
            case when v_target_type='company' then v_target_id end,case when v_target_type='opportunity' then v_target_id end,case when v_target_type='application' then v_target_id end)
          returning id into v_task_id;
        if v_target_type='contact' then insert into public.task_contacts(owner_id,task_id,contact_id) values(v_owner,v_task_id,v_target_id); end if;
        insert into public.task_events(owner_id,task_id,event_type,occurred_at,note,operation_key)
          values(v_owner,v_task_id,'created',timezone('utc',now()),btrim(v_action->>'reason_es'),p_operation_key||':action-'||(v_action->>'rank')||':task-created') returning id into v_event_id;
      end if;
    elsif v_task_mode='update' then
      v_task_id:=(v_task_effect->>'task_id')::uuid;
      select * into v_task from public.tasks where owner_id=v_owner and id=v_task_id and authority_state='commitment' for update;
      if not found or v_task.lock_version<>(v_task_effect->>'expected_lock_version')::bigint then raise exception 'task changed or unavailable' using errcode='PT409'; end if;
      if v_task.state in ('2-Completada','4-Cancelada') then raise exception 'terminal task cannot be updated by weekly guidance' using errcode='22023'; end if;
      if v_task_effect ? 'priority' and coalesce(v_task_effect->>'priority','') not in ('P0','P1','P2','P3') then raise exception 'invalid task priority' using errcode='22023'; end if;
      if v_task_effect ? 'due_at' and (v_task_effect->>'due_at')::timestamptz<v_cutoff then raise exception 'task due date precedes cutoff' using errcode='22023'; end if;
      update public.tasks set title=coalesce(nullif(btrim(v_task_effect->>'title'),''),title),priority=case when v_task_effect?'priority' then v_task_effect->>'priority' else priority end,due_at=case when v_task_effect?'due_at' then (v_task_effect->>'due_at')::timestamptz else due_at end where owner_id=v_owner and id=v_task_id;
      insert into public.task_events(owner_id,task_id,event_type,occurred_at,note,operation_key)
        values(v_owner,v_task_id,'corrected',timezone('utc',now()),btrim(v_action->>'reason_es'),p_operation_key||':action-'||(v_action->>'rank')||':task-corrected') returning id into v_event_id;
    elsif v_task_mode='reuse' then
      v_task_id:=nullif(v_task_effect->>'task_id','')::uuid;
      if v_task_id is null then select a.task_id into v_task_id from public.weekly_career_actions a join public.tasks t on t.owner_id=a.owner_id and t.id=a.task_id where a.owner_id=v_owner and a.action_identity=(v_action->>'action_identity') and t.authority_state='commitment' and t.state not in ('2-Completada','4-Cancelada') order by a.created_at desc limit 1; end if;
      if v_task_id is null or not exists(select 1 from public.tasks where owner_id=v_owner and id=v_task_id and authority_state='commitment' and state not in ('2-Completada','4-Cancelada')) then raise exception 'equivalent task unavailable' using errcode='P0002'; end if;
    end if;

    insert into public.weekly_career_actions(owner_id,review_id,rank,action_key,action_identity,classification,target_type,target_id,evidence_state,evidence_refs,reason_es,next_step_es,suggested_due_at,opportunity_id,opportunity_effect,task_id,task_event_id,task_effect_mode)
      values(v_owner,v_review_id,(v_action->>'rank')::smallint,btrim(v_action->>'action_key'),btrim(v_action->>'action_identity'),v_class,v_target_type,v_target_id,v_evidence_state,v_action->'evidence_refs',btrim(v_action->>'reason_es'),btrim(v_action->>'next_step_es'),nullif(v_action->>'suggested_due_at','')::timestamptz,v_opp_id,
        case when v_opp_id is null then null else jsonb_build_object('before',v_before,'after',v_after) end,v_task_id,v_event_id,v_task_mode);
    v_result_ids:=v_result_ids||jsonb_build_array(jsonb_build_object('type','weekly_career_action','rank',(v_action->>'rank')::int));
    if v_event_id is not null then v_result_ids:=v_result_ids||jsonb_build_array(jsonb_build_object('type','task_event','id',v_event_id)); end if;
  end loop;

  insert into public.operation_receipts(owner_id,operation_key,operation_type,request_sha256,result_record_ids)
    values(v_owner,p_operation_key,'weekly_career_guidance',v_hash,v_result_ids);
  return public.read_back_weekly_career_guidance(p_operation_key);
end;
$$;

revoke all on function public.get_weekly_career_guidance_context(integer) from public, anon;
revoke all on function public.record_weekly_career_guidance(jsonb,text) from public, anon;
revoke all on function public.read_back_weekly_career_guidance(text) from public, anon;
grant execute on function public.get_weekly_career_guidance_context(integer) to authenticated;
grant execute on function public.record_weekly_career_guidance(jsonb,text) to authenticated;
grant execute on function public.read_back_weekly_career_guidance(text) to authenticated;

comment on function public.get_weekly_career_guidance_context(integer) is 'Bounded owner context for weekly Product/AI career orientation; invoker RLS and no writes.';
comment on function public.record_weekly_career_guidance(jsonb,text) is 'Atomically records exactly three evidence-bounded weekly actions and only reviewed task/opportunity effects.';
comment on function public.read_back_weekly_career_guidance(text) is 'Authoritative receipt, review, actions, and affected task/opportunity readback for one weekly operation key.';
