-- FR-059: complete owner-only application register, independent of dashboard exclusions.
create or replace function public.get_application_register()
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(x) order by x.submitted_at desc,x.id),'[]'::jsonb)
 from (
 select a.id,c.name company_name,coalesce(j.title,o.title) role_title,a.submitted_at,a.channel,
 state.event_type current_state,state.occurred_at state_recorded_at,
 latest.event_type latest_event_type,latest.occurred_at latest_event_at,latest.note latest_event_note
 from public.applications a
 join public.companies c on c.owner_id=a.owner_id and c.id=a.company_id
 left join public.job_postings j on j.owner_id=a.owner_id and j.id=a.job_posting_id
 left join public.opportunities o on o.owner_id=a.owner_id and o.id=a.opportunity_id
 left join lateral (
 select e.event_type,e.occurred_at from public.application_events e
 where e.owner_id=a.owner_id and e.application_id=a.id
 and e.event_type in ('submitted','interview','withdrawn','rejected','offer','accepted','reopened')
 order by e.occurred_at desc,e.created_at desc,e.id desc limit 1
 ) state on true
 left join lateral (
 select e.event_type,e.occurred_at,e.note from public.application_events e
 where e.owner_id=a.owner_id and e.application_id=a.id
 order by e.created_at desc,e.id desc limit 1
 ) latest on true
 where a.owner_id=(select auth.uid())
 ) x;
$$;
revoke all on function public.get_application_register() from public,anon;
grant execute on function public.get_application_register() to authenticated;
