-- Orbit CRM core relational schema.
-- All relationships include owner_id so PostgreSQL rejects cross-owner links.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc', now());
  new.lock_version = old.lock_version + 1;
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

create table public.crm_owner_profiles (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0)
);

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  normalized_name text generated always as (lower(btrim(name))) stored,
  website_url text,
  linkedin_url text,
  careers_url text,
  headquarters text,
  size_band text,
  priority text,
  strategic_fit text,
  fit_reason text,
  notes text,
  segments text[] not null default '{}',
  markets text[] not null default '{}',
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  unique (owner_id, normalized_name),
  check (strategic_fit is null or strategic_fit in ('Alto', 'Medio', 'Bajo')),
  check (priority is null or priority in ('Target A', 'Target B', 'Watchlist', 'No fit'))
);

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  email text,
  phone text,
  linkedin_url text,
  job_title text,
  location text,
  contact_type text,
  source_channel text,
  relationship_strength text,
  relationship_state text,
  priority text,
  strategic_value text,
  territories text[] not null default '{}',
  cadence_days smallint check (cadence_days is null or cadence_days > 0),
  last_contact_at timestamptz,
  next_follow_up_at timestamptz,
  personalized_message text,
  context_notes text,
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  check (priority is null or priority in ('P0', 'P1', 'P2', 'P3')),
  check (relationship_strength is null or relationship_strength in ('Fuerte', 'Media', 'Debil', 'Nueva', 'Por activar'))
);

create unique index contacts_owner_email_uq
  on public.contacts (owner_id, lower(btrim(email)))
  where email is not null and btrim(email) <> '';

create unique index contacts_owner_linkedin_uq
  on public.contacts (owner_id, lower(btrim(linkedin_url)))
  where linkedin_url is not null and btrim(linkedin_url) <> '';

create table public.contact_company_affiliations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  contact_id uuid not null,
  company_id uuid not null,
  relationship_type text not null default 'unspecified' check (btrim(relationship_type) <> ''),
  started_on date,
  ended_on date,
  current_state text not null default 'unknown' check (current_state in ('current', 'former', 'unknown')),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  foreign key (owner_id, contact_id) references public.contacts(owner_id, id) on delete cascade,
  foreign key (owner_id, company_id) references public.companies(owner_id, id) on delete cascade,
  check (started_on is null or ended_on is null or started_on <= ended_on),
  check (current_state <> 'current' or ended_on is null)
);

create unique index contact_company_affiliations_identity_uq
  on public.contact_company_affiliations (
    owner_id,
    contact_id,
    company_id,
    relationship_type,
    coalesce(started_on, '-infinity'::date)
  );

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  company_id uuid not null,
  title text not null check (btrim(title) <> ''),
  status text,
  priority text,
  source_type text,
  opened_on date,
  last_movement_at timestamptz,
  next_step_at timestamptz,
  next_step text,
  target_role text,
  role_fit text,
  sector_fit text,
  risk_level text,
  primary_risk text,
  narratives text[] not null default '{}',
  location text,
  work_mode text,
  estimated_compensation text,
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  unique (owner_id, id, company_id),
  foreign key (owner_id, company_id) references public.companies(owner_id, id) on delete restrict,
  check (priority is null or priority in ('P0', 'P1', 'P2', 'P3')),
  check (role_fit is null or role_fit in ('Alto', 'Medio', 'Bajo')),
  check (sector_fit is null or sector_fit in ('Alto', 'Medio', 'Bajo')),
  check (risk_level is null or risk_level in ('Alto', 'Medio', 'Bajo')),
  check (work_mode is null or work_mode in ('Remoto', 'Hibrido', 'Presencial', 'Por definir'))
);

create table public.opportunity_contacts (
  owner_id uuid not null,
  opportunity_id uuid not null,
  contact_id uuid not null,
  role text not null check (role in ('recruiter', 'sponsor_referral', 'decision_maker', 'other')),
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, opportunity_id, contact_id, role),
  foreign key (owner_id, opportunity_id) references public.opportunities(owner_id, id) on delete cascade,
  foreign key (owner_id, contact_id) references public.contacts(owner_id, id) on delete restrict
);

create table public.job_postings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  company_id uuid not null,
  opportunity_id uuid,
  title text not null check (btrim(title) <> ''),
  source_url text,
  source_identifier text,
  source_name text,
  status text not null default 'unknown' check (status in ('unknown', 'open', 'closed', 'unavailable')),
  first_seen_at timestamptz not null,
  last_seen_at timestamptz,
  incomplete_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  unique (owner_id, id, company_id),
  foreign key (owner_id, company_id) references public.companies(owner_id, id) on delete restrict,
  foreign key (owner_id, opportunity_id, company_id)
    references public.opportunities(owner_id, id, company_id) on delete restrict,
  check (last_seen_at is null or last_seen_at >= first_seen_at),
  check (source_url is not null or source_identifier is not null or incomplete_reason is not null)
);

create unique index job_postings_source_identity_uq
  on public.job_postings (owner_id, source_name, source_identifier)
  where source_name is not null and source_identifier is not null;

create unique index job_postings_source_url_uq
  on public.job_postings (owner_id, source_url)
  where source_url is not null;

create table public.job_description_snapshots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  job_posting_id uuid not null,
  captured_at timestamptz not null,
  content_text text,
  content_sha256 text,
  source_url text,
  unavailable_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, id, job_posting_id),
  foreign key (owner_id, job_posting_id) references public.job_postings(owner_id, id) on delete cascade,
  check (content_text is not null or unavailable_reason is not null),
  check (content_sha256 is null or content_sha256 ~ '^[0-9a-f]{64}$')
);

create unique index job_description_snapshots_content_uq
  on public.job_description_snapshots (owner_id, job_posting_id, content_sha256)
  where content_sha256 is not null;

create table public.materials (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  normalized_name text generated always as (lower(btrim(name))) stored,
  material_type text,
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  unique (owner_id, normalized_name)
);

create table public.material_versions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  material_id uuid not null,
  version_label text not null check (btrim(version_label) <> ''),
  state text not null default 'Draft' check (state in ('Draft', 'Listo', 'Enviado', 'Necesita ajuste', 'Obsoleto')),
  external_url text,
  notes text,
  territories text[] not null default '{}',
  approved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, material_id, version_label),
  foreign key (owner_id, material_id) references public.materials(owner_id, id) on delete restrict
);

create table public.material_files (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  material_version_id uuid not null,
  storage_bucket text not null default 'orbit-materials' check (storage_bucket = 'orbit-materials'),
  storage_object_path text not null check (btrim(storage_object_path) <> ''),
  original_filename text not null check (btrim(original_filename) <> ''),
  media_type text,
  byte_size bigint check (byte_size is null or byte_size >= 0),
  sha256 text,
  source_attachment_id text,
  migration_state text not null default 'pending' check (migration_state in ('pending', 'verified', 'missing', 'failed')),
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, storage_bucket, storage_object_path),
  unique (owner_id, material_version_id, sha256),
  foreign key (owner_id, material_version_id) references public.material_versions(owner_id, id) on delete restrict,
  check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$')
);

create table public.opportunity_material_versions (
  owner_id uuid not null,
  opportunity_id uuid not null,
  material_version_id uuid not null,
  purpose text,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, opportunity_id, material_version_id),
  foreign key (owner_id, opportunity_id) references public.opportunities(owner_id, id) on delete cascade,
  foreign key (owner_id, material_version_id) references public.material_versions(owner_id, id) on delete restrict
);

create table public.candidate_profile_versions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  version_label text not null check (btrim(version_label) <> ''),
  profile_data jsonb not null,
  approved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, version_label)
);

create table public.scoring_rubric_versions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  version_label text not null check (btrim(version_label) <> ''),
  rubric_data jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, version_label)
);

create table public.fit_assessments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  job_posting_id uuid not null,
  job_description_snapshot_id uuid,
  candidate_profile_version_id uuid not null,
  scoring_rubric_version_id uuid not null,
  score numeric(5,2),
  confidence numeric(5,4),
  rationale text,
  strengths jsonb not null default '[]'::jsonb,
  gaps jsonb not null default '[]'::jsonb,
  constraints jsonb not null default '[]'::jsonb,
  assessed_at timestamptz not null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  foreign key (owner_id, job_posting_id) references public.job_postings(owner_id, id) on delete restrict,
  foreign key (owner_id, job_description_snapshot_id, job_posting_id)
    references public.job_description_snapshots(owner_id, id, job_posting_id) on delete restrict,
  foreign key (owner_id, candidate_profile_version_id)
    references public.candidate_profile_versions(owner_id, id) on delete restrict,
  foreign key (owner_id, scoring_rubric_version_id)
    references public.scoring_rubric_versions(owner_id, id) on delete restrict,
  check (score is null or score between 0 and 100),
  check (confidence is null or confidence between 0 and 1)
);

create table public.applications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  company_id uuid not null,
  opportunity_id uuid,
  job_posting_id uuid,
  submission_snapshot_id uuid,
  submitted_at timestamptz not null,
  channel text not null check (btrim(channel) <> ''),
  source_url text,
  source_identifier text,
  submission_evidence text,
  missing_snapshot_reason text,
  missing_material_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  foreign key (owner_id, company_id) references public.companies(owner_id, id) on delete restrict,
  foreign key (owner_id, opportunity_id, company_id)
    references public.opportunities(owner_id, id, company_id) on delete restrict,
  foreign key (owner_id, job_posting_id, company_id)
    references public.job_postings(owner_id, id, company_id) on delete restrict,
  foreign key (owner_id, submission_snapshot_id, job_posting_id)
    references public.job_description_snapshots(owner_id, id, job_posting_id) on delete restrict,
  check (submission_snapshot_id is null or job_posting_id is not null),
  check (job_posting_id is null or submission_snapshot_id is not null or missing_snapshot_reason is not null),
  check (submission_evidence is not null or source_url is not null or source_identifier is not null)
);

create table public.application_material_versions (
  owner_id uuid not null,
  application_id uuid not null,
  material_version_id uuid not null,
  purpose text not null default 'submitted',
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, application_id, material_version_id),
  foreign key (owner_id, application_id) references public.applications(owner_id, id) on delete cascade,
  foreign key (owner_id, material_version_id) references public.material_versions(owner_id, id) on delete restrict
);

create table public.application_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  application_id uuid not null,
  event_type text not null check (event_type in (
    'submitted', 'follow_up', 'interview', 'withdrawn', 'rejected', 'offer',
    'accepted', 'reopened', 'correction', 'other'
  )),
  occurred_at timestamptz not null,
  note text,
  evidence_url text,
  operation_key text not null check (btrim(operation_key) <> ''),
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, operation_key),
  foreign key (owner_id, application_id) references public.applications(owner_id, id) on delete cascade
);

create table public.interactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  interaction_type text,
  occurred_at timestamptz not null,
  summary text,
  insight text,
  result text,
  next_step text,
  follow_up_at timestamptz,
  context_company_id uuid,
  context_opportunity_id uuid,
  context_application_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  foreign key (owner_id, context_company_id) references public.companies(owner_id, id) on delete restrict,
  foreign key (owner_id, context_opportunity_id) references public.opportunities(owner_id, id) on delete restrict,
  foreign key (owner_id, context_application_id) references public.applications(owner_id, id) on delete restrict,
  check (num_nonnulls(context_company_id, context_opportunity_id, context_application_id) <= 1)
);

create table public.interaction_contacts (
  owner_id uuid not null,
  interaction_id uuid not null,
  contact_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, interaction_id, contact_id),
  foreign key (owner_id, interaction_id) references public.interactions(owner_id, id) on delete cascade,
  foreign key (owner_id, contact_id) references public.contacts(owner_id, id) on delete restrict
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  task_type text,
  state text not null default '0-Backlog' check (state in ('0-Backlog', '1-En curso', '2-Completada', '3-Bloqueada', '4-Cancelada')),
  authority_state text not null default 'commitment' check (authority_state in ('proposal', 'commitment', 'rejected')),
  priority text,
  due_at timestamptz,
  effort_minutes integer check (effort_minutes is null or effort_minutes > 0),
  energy_block text,
  notes text,
  source_interaction_id uuid,
  context_company_id uuid,
  context_opportunity_id uuid,
  context_application_id uuid,
  completed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  foreign key (owner_id, source_interaction_id) references public.interactions(owner_id, id) on delete restrict,
  foreign key (owner_id, context_company_id) references public.companies(owner_id, id) on delete restrict,
  foreign key (owner_id, context_opportunity_id) references public.opportunities(owner_id, id) on delete restrict,
  foreign key (owner_id, context_application_id) references public.applications(owner_id, id) on delete restrict,
  check (num_nonnulls(context_company_id, context_opportunity_id, context_application_id) <= 1),
  check (priority is null or priority in ('P0', 'P1', 'P2', 'P3')),
  check ((state = '2-Completada' and completed_at is not null) or (state <> '2-Completada' and completed_at is null)),
  check (authority_state = 'commitment' or due_at is null)
);

create table public.task_contacts (
  owner_id uuid not null,
  task_id uuid not null,
  contact_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, task_id, contact_id),
  foreign key (owner_id, task_id) references public.tasks(owner_id, id) on delete cascade,
  foreign key (owner_id, contact_id) references public.contacts(owner_id, id) on delete restrict
);

create table public.task_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null,
  task_id uuid not null,
  event_type text not null check (event_type in ('created', 'accepted', 'postponed', 'started', 'completed', 'blocked', 'cancelled', 'reopened', 'corrected')),
  occurred_at timestamptz not null,
  note text,
  operation_key text not null check (btrim(operation_key) <> ''),
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, operation_key),
  foreign key (owner_id, task_id) references public.tasks(owner_id, id) on delete cascade
);

create table public.market_signals (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  title text not null check (btrim(title) <> ''),
  signal_type text,
  signal_date date,
  source_url text,
  relevance text check (relevance is null or relevance in ('Alta', 'Media', 'Baja')),
  state text check (state is null or state in ('Nueva', 'Usada en outreach', 'Archivada')),
  search_implication text,
  suggested_action text,
  notes text,
  context_company_id uuid,
  context_opportunity_id uuid,
  context_job_posting_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  lock_version bigint not null default 1 check (lock_version > 0),
  unique (owner_id, id),
  foreign key (owner_id, context_company_id) references public.companies(owner_id, id) on delete restrict,
  foreign key (owner_id, context_opportunity_id) references public.opportunities(owner_id, id) on delete restrict,
  foreign key (owner_id, context_job_posting_id) references public.job_postings(owner_id, id) on delete restrict,
  check (num_nonnulls(context_company_id, context_opportunity_id, context_job_posting_id) <= 1)
);

create table public.operation_receipts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  operation_key text not null check (btrim(operation_key) <> ''),
  operation_type text not null check (btrim(operation_type) <> ''),
  request_sha256 text not null check (request_sha256 ~ '^[0-9a-f]{64}$'),
  result_record_ids jsonb not null default '[]'::jsonb,
  completed_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, operation_key)
);

create table public.source_records (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  source_system text not null check (btrim(source_system) <> ''),
  source_database text not null check (btrim(source_database) <> ''),
  source_record_id text not null check (btrim(source_record_id) <> ''),
  source_url text,
  source_created_at timestamptz,
  source_updated_at timestamptz,
  source_sha256 text check (source_sha256 is null or source_sha256 ~ '^[0-9a-f]{64}$'),
  import_batch_id uuid,
  reconciliation_state text not null default 'pending' check (reconciliation_state in ('pending', 'mapped', 'merged', 'skipped', 'failed')),
  company_id uuid,
  contact_id uuid,
  opportunity_id uuid,
  job_posting_id uuid,
  application_id uuid,
  interaction_id uuid,
  task_id uuid,
  material_version_id uuid,
  market_signal_id uuid,
  created_at timestamptz not null default timezone('utc', now()),
  unique (owner_id, id),
  unique (owner_id, source_system, source_database, source_record_id),
  foreign key (owner_id, company_id) references public.companies(owner_id, id) on delete restrict,
  foreign key (owner_id, contact_id) references public.contacts(owner_id, id) on delete restrict,
  foreign key (owner_id, opportunity_id) references public.opportunities(owner_id, id) on delete restrict,
  foreign key (owner_id, job_posting_id) references public.job_postings(owner_id, id) on delete restrict,
  foreign key (owner_id, application_id) references public.applications(owner_id, id) on delete restrict,
  foreign key (owner_id, interaction_id) references public.interactions(owner_id, id) on delete restrict,
  foreign key (owner_id, task_id) references public.tasks(owner_id, id) on delete restrict,
  foreign key (owner_id, material_version_id) references public.material_versions(owner_id, id) on delete restrict,
  foreign key (owner_id, market_signal_id) references public.market_signals(owner_id, id) on delete restrict,
  check (num_nonnulls(
    company_id, contact_id, opportunity_id, job_posting_id, application_id,
    interaction_id, task_id, material_version_id, market_signal_id
  ) = 1)
);

create or replace function private.validate_application_context()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  posting_opportunity_id uuid;
begin
  if new.job_posting_id is not null and new.opportunity_id is not null then
    select jp.opportunity_id
      into posting_opportunity_id
      from public.job_postings jp
     where jp.owner_id = new.owner_id
       and jp.id = new.job_posting_id;

    if posting_opportunity_id is not null and posting_opportunity_id <> new.opportunity_id then
      raise exception using
        errcode = '23514',
        message = 'application opportunity does not match job posting opportunity';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.validate_application_context() from public, anon, authenticated;

create or replace function private.prevent_row_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception '% rows are append-only and cannot be updated', tg_table_name;
end;
$$;

revoke all on function private.prevent_row_update() from public, anon, authenticated;

create or replace function private.protect_referenced_material_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.application_material_versions amv
    where amv.owner_id = old.owner_id
      and amv.material_version_id = old.id
  ) then
    raise exception 'material version % is part of application evidence', old.id;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.protect_referenced_material_version() from public, anon, authenticated;

create trigger applications_validate_context
before insert or update of owner_id, company_id, opportunity_id, job_posting_id
on public.applications
for each row execute function private.validate_application_context();

create trigger job_description_snapshots_append_only
before update on public.job_description_snapshots
for each row execute function private.prevent_row_update();

create trigger application_events_append_only
before update on public.application_events
for each row execute function private.prevent_row_update();

create trigger task_events_append_only
before update on public.task_events
for each row execute function private.prevent_row_update();

create trigger material_versions_protect_application_evidence
before update or delete on public.material_versions
for each row execute function private.protect_referenced_material_version();

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'crm_owner_profiles', 'companies', 'contacts', 'opportunities', 'job_postings', 'materials',
    'applications', 'interactions', 'tasks', 'market_signals'
  ]
  loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function private.set_updated_at()',
      table_name || '_set_updated_at',
      table_name
    );
  end loop;
end;
$$;

create index contact_company_affiliations_company_idx
  on public.contact_company_affiliations (owner_id, company_id, contact_id);
create index opportunities_company_status_idx
  on public.opportunities (owner_id, company_id, status);
create index opportunity_contacts_contact_idx
  on public.opportunity_contacts (owner_id, contact_id, opportunity_id);
create index job_postings_company_status_idx
  on public.job_postings (owner_id, company_id, status);
create index job_postings_opportunity_idx
  on public.job_postings (owner_id, opportunity_id) where opportunity_id is not null;
create index job_description_snapshots_posting_captured_idx
  on public.job_description_snapshots (owner_id, job_posting_id, captured_at desc);
create index material_versions_material_idx
  on public.material_versions (owner_id, material_id, created_at desc);
create index material_files_version_idx
  on public.material_files (owner_id, material_version_id);
create index opportunity_material_versions_material_idx
  on public.opportunity_material_versions (owner_id, material_version_id, opportunity_id);
create index fit_assessments_posting_idx
  on public.fit_assessments (owner_id, job_posting_id, assessed_at desc);
create index applications_company_submitted_idx
  on public.applications (owner_id, company_id, submitted_at desc);
create index applications_opportunity_idx
  on public.applications (owner_id, opportunity_id) where opportunity_id is not null;
create index applications_job_posting_idx
  on public.applications (owner_id, job_posting_id) where job_posting_id is not null;
create index application_material_versions_material_idx
  on public.application_material_versions (owner_id, material_version_id, application_id);
create index application_events_timeline_idx
  on public.application_events (owner_id, application_id, occurred_at, id);
create index interactions_timeline_idx
  on public.interactions (owner_id, occurred_at desc);
create index interaction_contacts_contact_idx
  on public.interaction_contacts (owner_id, contact_id, interaction_id);
create index tasks_due_idx
  on public.tasks (owner_id, state, due_at) where authority_state = 'commitment';
create index task_contacts_contact_idx
  on public.task_contacts (owner_id, contact_id, task_id);
create index task_events_timeline_idx
  on public.task_events (owner_id, task_id, occurred_at, id);
create index market_signals_date_idx
  on public.market_signals (owner_id, signal_date desc);
create index source_records_target_company_idx
  on public.source_records (owner_id, company_id) where company_id is not null;
create index source_records_target_contact_idx
  on public.source_records (owner_id, contact_id) where contact_id is not null;
create index source_records_target_opportunity_idx
  on public.source_records (owner_id, opportunity_id) where opportunity_id is not null;
create index source_records_target_interaction_idx
  on public.source_records (owner_id, interaction_id) where interaction_id is not null;
create index source_records_target_task_idx
  on public.source_records (owner_id, task_id) where task_id is not null;
create index source_records_target_material_idx
  on public.source_records (owner_id, material_version_id) where material_version_id is not null;

comment on table public.contact_company_affiliations is
  'Contact-company relationships, including historical employment. Unknown current state remains unknown.';
comment on table public.opportunity_contacts is
  'Role-qualified opportunity-contact links; duplicate links are rejected by the primary key.';
comment on table public.opportunity_material_versions is
  'Many-to-many link between opportunities and exact material versions.';
comment on table public.source_records is
  'External-source crosswalk. Exactly one authoritative Orbit target is required per source record.';
