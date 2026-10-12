-- Owner-only access baseline for Orbit CRM.
-- Ordinary authenticated clients receive read access only; writes will use reviewed RPCs.

grant usage on schema public to authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'crm_owner_profiles',
    'companies',
    'contacts',
    'contact_company_affiliations',
    'opportunities',
    'opportunity_contacts',
    'job_postings',
    'job_description_snapshots',
    'materials',
    'material_versions',
    'material_files',
    'opportunity_material_versions',
    'candidate_profile_versions',
    'scoring_rubric_versions',
    'fit_assessments',
    'applications',
    'application_material_versions',
    'application_events',
    'interactions',
    'interaction_contacts',
    'tasks',
    'task_contacts',
    'task_events',
    'market_signals',
    'operation_receipts',
    'source_records'
  ]
  loop
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
    execute format('grant select on table public.%I to authenticated', table_name);
    execute format(
      'create policy owner_read on public.%I for select to authenticated using ((select auth.uid()) = owner_id)',
      table_name
    );
  end loop;
end;
$$;

create or replace view public.current_application_states
with (security_invoker = true)
as
select distinct on (a.owner_id, a.id)
  a.owner_id,
  a.id as application_id,
  e.event_type as current_state,
  e.occurred_at as state_recorded_at,
  e.id as application_event_id
from public.applications a
left join public.application_events e
  on e.owner_id = a.owner_id
 and e.application_id = a.id
order by a.owner_id, a.id, e.occurred_at desc nulls last, e.id desc;

create or replace view public.contact_company_context
with (security_invoker = true)
as
select
  a.owner_id,
  a.contact_id,
  a.company_id,
  a.relationship_type,
  a.current_state,
  a.started_on,
  a.ended_on
from public.contact_company_affiliations a;

grant select on public.current_application_states to authenticated;
grant select on public.contact_company_context to authenticated;

revoke all on function private.set_updated_at() from public, anon, authenticated;
revoke all on function private.validate_application_context() from public, anon, authenticated;
revoke all on function private.prevent_row_update() from public, anon, authenticated;
revoke all on function private.protect_referenced_material_version() from public, anon, authenticated;

comment on view public.current_application_states is
  'Current application state derived from immutable events; job-posting status cannot change it.';
comment on view public.contact_company_context is
  'Inverse company/contact navigation derived from one canonical affiliation relation.';
