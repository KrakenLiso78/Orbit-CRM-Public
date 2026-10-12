-- Promote an owner-selected monitored posting into a CRM opportunity.
-- This decision is deliberately separate from a submitted application.
-- Traceability: root FR-046-047; monitor FR-037-038; CRM FR-046-047.
create or replace function public.read_back_job_posting_promotion(p_operation_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
  v_job_id uuid;
  v_opportunity_id uuid;
begin
  select * into v_receipt
  from public.operation_receipts
  where owner_id = v_owner
    and operation_key = btrim(p_operation_key)
    and operation_type = 'promote_job_posting_to_opportunity';

  if not found then
    raise exception 'job posting promotion receipt was not found' using errcode = 'P0002';
  end if;

  select (entry ->> 'id')::uuid into v_job_id
  from jsonb_array_elements(v_receipt.result_record_ids) entry
  where entry ->> 'type' = 'job_posting'
  limit 1;

  select (entry ->> 'id')::uuid into v_opportunity_id
  from jsonb_array_elements(v_receipt.result_record_ids) entry
  where entry ->> 'type' = 'opportunity'
  limit 1;

  return jsonb_build_object(
    'saved', true,
    'application_created', false,
    'receipt', to_jsonb(v_receipt) - 'owner_id',
    'job_posting', (
      select jsonb_build_object(
        'id', j.id,
        'opportunity_id', j.opportunity_id,
        'title', j.title,
        'status', j.status,
        'source_url', j.source_url,
        'company_id', j.company_id
      )
      from public.job_postings j
      where j.owner_id = v_owner and j.id = v_job_id
    ),
    'opportunity', (
      select to_jsonb(o) - 'owner_id'
      from public.opportunities o
      where o.owner_id = v_owner and o.id = v_opportunity_id
    )
  );
end;
$$;

create or replace function public.promote_job_posting_to_opportunity(
  p_job_id uuid,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := private.require_call_report_owner();
  v_job public.job_postings%rowtype;
  v_receipt public.operation_receipts%rowtype;
  v_hash text;
  v_opportunity_id uuid;
  v_work_mode text;
begin
  if p_job_id is null or nullif(btrim(p_operation_key), '') is null then
    raise exception 'job_id and operation_key are required' using errcode = '22023';
  end if;

  v_hash := encode(
    extensions.digest(convert_to(p_job_id::text, 'UTF8'), 'sha256'),
    'hex'
  );

  select * into v_receipt
  from public.operation_receipts
  where owner_id = v_owner and operation_key = btrim(p_operation_key);

  if found then
    if v_receipt.operation_type <> 'promote_job_posting_to_opportunity'
       or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_job_posting_promotion(btrim(p_operation_key));
  end if;

  select * into v_job
  from public.job_postings
  where owner_id = v_owner and id = p_job_id
  for update;

  if not found then
    raise exception 'job posting was not found' using errcode = 'P0002';
  end if;
  if v_job.status <> 'open' then
    raise exception 'only an open job posting can be promoted' using errcode = '22023';
  end if;
  if v_job.source_url is null or v_job.source_url !~ '^https://' then
    raise exception 'an official https source URL is required' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.job_dismissals d
    where d.owner_id = v_owner and d.job_posting_id = p_job_id
  ) then
    raise exception 'a dismissed job posting cannot be promoted' using errcode = '22023';
  end if;

  v_opportunity_id := v_job.opportunity_id;
  if v_opportunity_id is null then
    v_work_mode := case lower(coalesce(v_job.work_arrangement, ''))
      when 'remote' then 'Remoto'
      when 'remoto' then 'Remoto'
      when 'hybrid' then 'Hibrido'
      when 'híbrido' then 'Hibrido'
      when 'hibrido' then 'Hibrido'
      when 'on-site' then 'Presencial'
      when 'onsite' then 'Presencial'
      when 'presencial' then 'Presencial'
      else null
    end;

    insert into public.opportunities (
      owner_id, company_id, title, status, source_type, opened_on,
      last_movement_at, next_step, target_role, location, work_mode, notes
    ) values (
      v_owner, v_job.company_id, v_job.title, 'Open', 'job_monitor', current_date,
      timezone('utc', now()), 'Submit application through the official careers page.',
      v_job.title, v_job.location, v_work_mode,
      'Promoted from an owner-selected monitored job posting. No application has been recorded.'
    ) returning id into v_opportunity_id;

    update public.job_postings
    set opportunity_id = v_opportunity_id,
        updated_at = timezone('utc', now()),
        lock_version = lock_version + 1
    where owner_id = v_owner and id = p_job_id;
  else
    perform 1
    from public.opportunities o
    where o.owner_id = v_owner
      and o.id = v_opportunity_id
      and o.company_id = v_job.company_id
      and o.archived_at is null;
    if not found then
      raise exception 'linked opportunity is unavailable' using errcode = 'P0002';
    end if;
  end if;

  insert into public.operation_receipts (
    owner_id, operation_key, operation_type, request_sha256, result_record_ids
  ) values (
    v_owner,
    btrim(p_operation_key),
    'promote_job_posting_to_opportunity',
    v_hash,
    jsonb_build_array(
      jsonb_build_object('type', 'job_posting', 'id', p_job_id),
      jsonb_build_object('type', 'opportunity', 'id', v_opportunity_id)
    )
  );

  return public.read_back_job_posting_promotion(btrim(p_operation_key));
end;
$$;

revoke all on function public.promote_job_posting_to_opportunity(uuid, text) from public, anon, authenticated;
revoke all on function public.read_back_job_posting_promotion(text) from public, anon, authenticated;
grant execute on function public.promote_job_posting_to_opportunity(uuid, text) to authenticated;
grant execute on function public.read_back_job_posting_promotion(text) to authenticated;

comment on function public.promote_job_posting_to_opportunity(uuid, text) is
  'Owner-scoped idempotent promotion of one open monitored posting into a linked CRM opportunity; never creates an application.';
comment on function public.read_back_job_posting_promotion(text) is
  'Authoritative owner-scoped readback for a monitored-posting promotion receipt.';
