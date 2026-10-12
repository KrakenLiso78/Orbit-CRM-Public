-- Only explicit active states belong in the active lane; retain all-record KPI.
create or replace function public.get_dashboard_snapshot(
  p_task_limit integer default 8,
  p_activity_limit integer default 8
)
returns jsonb
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'counts', jsonb_build_object(
      'companies', (select count(*) from public.companies where owner_id = (select auth.uid()) and archived_at is null),
      'contacts', (select count(*) from public.contacts where owner_id = (select auth.uid()) and archived_at is null),
      'opportunities', (select count(*) from public.opportunities where owner_id = (select auth.uid()) and archived_at is null),
      'applications', (select count(*) from public.applications where owner_id = (select auth.uid())),
      'open_tasks', (select count(*) from public.tasks where owner_id = (select auth.uid()) and state not in ('2-Completada', '4-Cancelada'))
    ),
    'due_tasks', coalesce((
      select jsonb_agg(to_jsonb(task_row) order by task_row.due_at nulls last, task_row.created_at desc)
      from (
        select id, title, state, priority, due_at, authority_state, context_company_id, context_opportunity_id, context_application_id, created_at
        from public.tasks
        where owner_id = (select auth.uid())
          and state not in ('2-Completada', '4-Cancelada')
        order by due_at nulls last, created_at desc
        limit greatest(1, least(coalesce(p_task_limit, 8), 50))
      ) as task_row
    ), '[]'::jsonb),
    'recent_completed_tasks', coalesce((
      select jsonb_agg(to_jsonb(completed_task_row) order by completed_task_row.completed_at desc, completed_task_row.created_at desc)
      from (
        select t.id, t.title, t.completed_at, t.created_at, t.source_interaction_id,
               i.title as source_interaction_title,
               coalesce((
                 select jsonb_agg(
                   jsonb_build_object(
                     'id', e.id,
                     'event_type', e.event_type,
                     'occurred_at', e.occurred_at,
                     'note', e.note
                   ) order by e.occurred_at, e.id
                 )
                 from public.task_events as e
                 where e.owner_id = t.owner_id and e.task_id = t.id
               ), '[]'::jsonb) as events
        from public.tasks as t
        left join public.interactions as i
          on i.owner_id = t.owner_id and i.id = t.source_interaction_id
        where t.owner_id = (select auth.uid())
          and t.state = '2-Completada'
        order by t.completed_at desc, t.created_at desc
        limit greatest(1, least(coalesce(p_activity_limit, 8), 50))
      ) as completed_task_row
    ), '[]'::jsonb),
    'recent_interactions', coalesce((
      select jsonb_agg(to_jsonb(interaction_row) order by interaction_row.occurred_at desc, interaction_row.created_at desc)
      from (
        select id, title, interaction_type, occurred_at, summary, result, next_step, follow_up_at, context_company_id, context_opportunity_id, context_application_id, created_at
        from public.interactions
        where owner_id = (select auth.uid())
        order by occurred_at desc, created_at desc
        limit greatest(1, least(coalesce(p_activity_limit, 8), 50))
      ) as interaction_row
    ), '[]'::jsonb),
    'active_opportunities', coalesce((
      select jsonb_agg(to_jsonb(opportunity_row) order by opportunity_row.next_step_at nulls last, opportunity_row.updated_at desc)
      from (
        select id, company_id, title, status, priority, target_role, next_step_at, next_step, role_fit, risk_level, updated_at
        from public.opportunities
        where owner_id = (select auth.uid()) and archived_at is null
          and lower(btrim(status)) in ('open', 'abierta', 'abierto', 'contacto hecho', 'contact made', 'screening', 'entrevista', 'interview', 'nueva', 'nuevo', 'new', 'en curso', 'in progress', 'negociación', 'negociacion', 'negotiation', 'propuesta', 'proposal')
        order by next_step_at nulls last, updated_at desc
        limit 12
      ) as opportunity_row
    ), '[]'::jsonb),
    'recent_applications', coalesce((
      select jsonb_agg(to_jsonb(application_row) order by application_row.submitted_at desc, application_row.created_at desc)
      from (
        select a.id, a.company_id, a.opportunity_id, a.job_posting_id, a.submitted_at,
               a.channel, a.source_url, a.created_at, c.name as company_name,
               coalesce(j.title, o.title) as role_title,
               current_state.event_type as current_state,
               current_state.occurred_at as state_recorded_at,
               latest_event.event_type as latest_event_type,
               latest_event.occurred_at as latest_event_at,
               latest_event.note as latest_event_note
        from public.applications as a
        join public.companies as c on c.owner_id = a.owner_id and c.id = a.company_id
        left join public.opportunities as o on o.owner_id = a.owner_id and o.id = a.opportunity_id
        left join public.job_postings as j on j.owner_id = a.owner_id and j.id = a.job_posting_id
        left join lateral (
          select e.event_type, e.occurred_at
          from public.application_events as e
          where e.owner_id = a.owner_id and e.application_id = a.id
            and e.event_type in ('submitted', 'interview', 'withdrawn', 'rejected', 'offer', 'accepted', 'reopened')
          order by e.occurred_at desc, e.created_at desc, e.id desc
          limit 1
        ) as current_state on true
        left join lateral (
          select e.event_type, e.occurred_at, e.note
          from public.application_events as e
          where e.owner_id = a.owner_id and e.application_id = a.id
          order by e.created_at desc, e.id desc
          limit 1
        ) as latest_event on true
        where a.owner_id = (select auth.uid())
        order by a.submitted_at desc, a.created_at desc
        limit 8
      ) as application_row
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.get_dashboard_snapshot(integer, integer) from public, anon;
grant execute on function public.get_dashboard_snapshot(integer, integer) to authenticated;

comment on function public.get_dashboard_snapshot(integer, integer) is
  'Bounded owner-scoped dashboard read with completed task and application histories. Uses invoker RLS and never exposes arbitrary SQL.';
