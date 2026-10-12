-- Reconcile previously discovered open postings against their official detail pages.
-- Closure evidence is retained without changing application state or historical fit assessments.

create or replace function public.list_open_job_postings_for_monitor(p_limit integer default 500)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
begin
  if v_owner_id is null then
    raise exception 'authentication is required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 1000 then
    raise exception 'limit must be between 1 and 1000' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'jobs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', j.id,
        'company_name', c.name,
        'title', j.title,
        'source_name', j.source_name,
        'source_identifier', j.source_identifier,
        'source_url', j.source_url,
        'status', j.status,
        'first_seen_at', j.first_seen_at,
        'last_seen_at', j.last_seen_at
      ) order by j.source_name, j.source_identifier)
      from (
        select *
        from public.job_postings
        where owner_id = v_owner_id
          and status = 'open'
          and source_name is not null
          and source_identifier is not null
          and source_url is not null
        order by source_name, source_identifier
        limit p_limit
      ) j
      join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.read_back_job_posting_status_checks(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_receipt public.operation_receipts%rowtype;
begin
  select * into v_receipt
  from public.operation_receipts
  where owner_id = v_owner_id
    and operation_key = p_operation_key
    and operation_type = 'record_job_posting_status_checks';

  if not found then
    raise exception 'job posting status-check receipt was not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'saved', true,
    'receipt', to_jsonb(v_receipt) - 'owner_id',
    'checks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'job', to_jsonb(j) - 'owner_id',
        'company_name', c.name,
        'evidence', to_jsonb(s) - 'owner_id'
      ) order by c.name, j.title)
      from public.job_postings j
      join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
      join lateral (
        select d.*
        from public.job_description_snapshots d
        where d.owner_id = j.owner_id
          and d.job_posting_id = j.id
          and d.id in (
            select (x ->> 'id')::uuid
            from jsonb_array_elements(v_receipt.result_record_ids) x
            where x ->> 'type' = 'job_status_snapshot'
          )
        order by d.captured_at desc
        limit 1
      ) s on true
      where j.owner_id = v_owner_id
        and j.id in (
          select (x ->> 'id')::uuid
          from jsonb_array_elements(v_receipt.result_record_ids) x
          where x ->> 'type' = 'job_posting_status'
        )
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.record_job_posting_status_checks(p_checks jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_hash text;
  v_receipt public.operation_receipts%rowtype;
  v_check jsonb;
  v_job_id uuid;
  v_snapshot_id uuid;
  v_status text;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null
     or jsonb_typeof(p_checks) <> 'array'
     or jsonb_array_length(p_checks) = 0 then
    raise exception 'checks and operation_key are required' using errcode = '22023';
  end if;

  v_hash := encode(extensions.digest(convert_to(p_checks::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt
  from public.operation_receipts
  where owner_id = v_owner_id and operation_key = p_operation_key;

  if found then
    if v_receipt.operation_type <> 'record_job_posting_status_checks'
       or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_job_posting_status_checks(p_operation_key);
  end if;

  for v_check in select value from jsonb_array_elements(p_checks)
  loop
    v_status := v_check ->> 'status';
    if jsonb_typeof(v_check) <> 'object'
       or nullif(btrim(v_check ->> 'source_name'), '') is null
       or nullif(btrim(v_check ->> 'source_identifier'), '') is null
       or coalesce(v_check ->> 'source_url', '') !~ '^https://'
       or v_status not in ('closed', 'unavailable')
       or nullif(btrim(v_check ->> 'reason'), '') is null
       or nullif(v_check ->> 'checked_at', '') is null then
      raise exception 'each check requires source identity, https URL, inactive status, checked_at, and reason' using errcode = '22023';
    end if;

    select id into v_job_id
    from public.job_postings
    where owner_id = v_owner_id
      and source_name = btrim(v_check ->> 'source_name')
      and source_identifier = btrim(v_check ->> 'source_identifier')
      and source_url = btrim(v_check ->> 'source_url');

    if v_job_id is null then
      raise exception 'open job posting was not found for the supplied official source identity' using errcode = 'P0002';
    end if;

    update public.job_postings
    set status = v_status,
        updated_at = timezone('utc', now()),
        lock_version = lock_version + 1
    where owner_id = v_owner_id and id = v_job_id;

    insert into public.job_description_snapshots(
      owner_id, job_posting_id, captured_at, source_url, unavailable_reason
    ) values (
      v_owner_id, v_job_id, (v_check ->> 'checked_at')::timestamptz,
      btrim(v_check ->> 'source_url'), btrim(v_check ->> 'reason')
    ) returning id into v_snapshot_id;

    update public.private_notifications
    set state = 'archived'
    where owner_id = v_owner_id
      and notification_type = 'job_shortlist'
      and body ->> 'job_posting_id' = v_job_id::text
      and state = 'unread';

    v_result_ids := v_result_ids || jsonb_build_array(
      jsonb_build_object('type', 'job_posting_status', 'id', v_job_id),
      jsonb_build_object('type', 'job_status_snapshot', 'id', v_snapshot_id)
    );
  end loop;

  insert into public.operation_receipts(
    owner_id, operation_key, operation_type, request_sha256, result_record_ids
  ) values (
    v_owner_id, p_operation_key, 'record_job_posting_status_checks', v_hash, v_result_ids
  );

  return public.read_back_job_posting_status_checks(p_operation_key);
end;
$$;

revoke all on function public.list_open_job_postings_for_monitor(integer) from public, anon;
revoke all on function public.record_job_posting_status_checks(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_job_posting_status_checks(text) from public, anon, authenticated;

grant execute on function public.list_open_job_postings_for_monitor(integer) to authenticated;
grant execute on function public.record_job_posting_status_checks(jsonb, text) to authenticated;
grant execute on function public.read_back_job_posting_status_checks(text) to authenticated;

comment on function public.list_open_job_postings_for_monitor(integer) is
  'Owner-scoped inventory of current open official postings that must be rechecked by the job monitor.';
comment on function public.record_job_posting_status_checks(jsonb, text) is
  'Mark verified postings closed or unavailable, retain official-source evidence, archive stale shortlist notifications, and preserve application history.';
comment on function public.read_back_job_posting_status_checks(text) is
  'Read authoritative posting lifecycle changes and evidence by operation key.';
