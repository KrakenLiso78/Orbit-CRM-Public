-- Performance slice: reuse owner session in the MCP layer and expose one bounded,
-- owner-scoped read for the first private dashboard view.

alter policy crm_corrections_owner_select on public.crm_corrections
  using ((select auth.uid()) = owner_id);

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
        order by next_step_at nulls last, updated_at desc
        limit 12
      ) as opportunity_row
    ), '[]'::jsonb),
    'recent_applications', coalesce((
      select jsonb_agg(to_jsonb(application_row) order by application_row.submitted_at desc, application_row.created_at desc)
      from (
        select a.id, a.company_id, a.opportunity_id, a.job_posting_id, a.submitted_at, a.channel, a.source_url, a.created_at,
               c.name as company_name
        from public.applications as a
        join public.companies as c on c.owner_id = a.owner_id and c.id = a.company_id
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
  'Bounded owner-scoped first dashboard read. Uses invoker RLS and never exposes arbitrary SQL.';
