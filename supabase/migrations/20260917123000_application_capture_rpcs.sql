-- Owner-scoped application capture with immutable material evidence.
-- Storage upload remains a Supabase Storage API action; this migration permits
-- authenticated owners to insert PDF objects only under their owner folder, then
-- records the verified object metadata through the audited RPC.

drop policy if exists orbit_materials_owner_pdf_insert on storage.objects;

create policy orbit_materials_owner_pdf_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'orbit-materials'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and lower(name) like '%.pdf'
);

create or replace function private.validate_application_capture(p_capture jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_application jsonb;
  v_material jsonb;
begin
  if jsonb_typeof(p_capture) <> 'object' then
    raise exception 'application capture must be a JSON object' using errcode = '22023';
  end if;

  for v_key in select jsonb_object_keys(p_capture)
  loop
    if v_key not in ('existing_application_id', 'application', 'materials', 'source') then
      raise exception 'unsupported application capture field: %', v_key using errcode = '22023';
    end if;
  end loop;

  if p_capture ? 'existing_application_id' then
    perform (p_capture ->> 'existing_application_id')::uuid;
  end if;

  if p_capture ? 'application' then
    v_application := p_capture -> 'application';
    if jsonb_typeof(v_application) <> 'object' then
      raise exception 'application must be an object' using errcode = '22023';
    end if;
    for v_key in select jsonb_object_keys(v_application)
    loop
      if v_key not in (
        'company_id', 'opportunity_id', 'job_posting_id', 'submission_snapshot_id',
        'submitted_at', 'channel', 'source_url', 'source_identifier',
        'submission_evidence', 'missing_snapshot_reason', 'missing_material_reason'
      ) then
        raise exception 'unsupported application field: %', v_key using errcode = '22023';
      end if;
    end loop;
    if jsonb_typeof(v_application -> 'company_id') <> 'string'
       or jsonb_typeof(v_application -> 'submitted_at') <> 'string'
       or jsonb_typeof(v_application -> 'channel') <> 'string'
       or btrim(v_application ->> 'channel') = '' then
      raise exception 'application company_id, submitted_at, and channel are required' using errcode = '22023';
    end if;
    perform (v_application ->> 'company_id')::uuid;
    perform (v_application ->> 'submitted_at')::timestamptz;
    if v_application ? 'opportunity_id' then perform (v_application ->> 'opportunity_id')::uuid; end if;
    if v_application ? 'job_posting_id' then perform (v_application ->> 'job_posting_id')::uuid; end if;
    if v_application ? 'submission_snapshot_id' then perform (v_application ->> 'submission_snapshot_id')::uuid; end if;
    if nullif(btrim(coalesce(v_application ->> 'submission_evidence', '')), '') is null
       and nullif(btrim(coalesce(v_application ->> 'source_url', '')), '') is null
       and nullif(btrim(coalesce(v_application ->> 'source_identifier', '')), '') is null then
      raise exception 'application requires source_url, source_identifier, or submission_evidence' using errcode = '22023';
    end if;
    if v_application ? 'job_posting_id'
       and not (v_application ? 'submission_snapshot_id')
       and nullif(btrim(coalesce(v_application ->> 'missing_snapshot_reason', '')), '') is null then
      raise exception 'job_posting application requires submission_snapshot_id or missing_snapshot_reason' using errcode = '22023';
    end if;
  end if;

  if not (p_capture ? 'existing_application_id') and not (p_capture ? 'application') then
    raise exception 'existing_application_id or application is required' using errcode = '22023';
  end if;

  if p_capture ? 'materials' then
    if jsonb_typeof(p_capture -> 'materials') <> 'array' then
      raise exception 'materials must be an array' using errcode = '22023';
    end if;
    for v_material in select value from jsonb_array_elements(p_capture -> 'materials')
    loop
      if jsonb_typeof(v_material) <> 'object' then
        raise exception 'each material must be an object' using errcode = '22023';
      end if;
      for v_key in select jsonb_object_keys(v_material)
      loop
        if v_key not in (
          'material_version_id', 'name', 'material_type', 'version_label', 'state',
          'external_url', 'notes', 'territories', 'approved_at', 'storage_object_path',
          'original_filename', 'media_type', 'byte_size', 'sha256',
          'source_attachment_id', 'migration_state', 'purpose'
        ) then
          raise exception 'unsupported material field: %', v_key using errcode = '22023';
        end if;
      end loop;
      if v_material ? 'material_version_id' then
        perform (v_material ->> 'material_version_id')::uuid;
      else
        if nullif(btrim(coalesce(v_material ->> 'name', '')), '') is null
           or nullif(btrim(coalesce(v_material ->> 'version_label', '')), '') is null then
          raise exception 'material name and version_label are required' using errcode = '22023';
        end if;
        if coalesce(nullif(btrim(v_material ->> 'state'), ''), 'Listo') not in ('Draft', 'Listo', 'Enviado', 'Necesita ajuste', 'Obsoleto') then
          raise exception 'material state is unsupported' using errcode = '22023';
        end if;
      end if;
      if v_material ? 'storage_object_path' then
        if nullif(btrim(v_material ->> 'storage_object_path'), '') is null
           or lower(v_material ->> 'storage_object_path') not like '%.pdf' then
          raise exception 'storage_object_path must be a PDF object path' using errcode = '22023';
        end if;
        if nullif(btrim(coalesce(v_material ->> 'original_filename', '')), '') is null then
          raise exception 'original_filename is required when storage_object_path is supplied' using errcode = '22023';
        end if;
      end if;
      if v_material ? 'sha256'
         and nullif(btrim(v_material ->> 'sha256'), '') is not null
         and v_material ->> 'sha256' !~ '^[0-9a-f]{64}$' then
        raise exception 'sha256 must be a lowercase SHA-256 hexadecimal digest' using errcode = '22023';
      end if;
      if v_material ? 'byte_size' and (v_material ->> 'byte_size')::bigint < 0 then
        raise exception 'byte_size must be non-negative' using errcode = '22023';
      end if;
    end loop;
  end if;
end;
$$;

create or replace function public.prepare_application_capture(p_capture jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_application_id uuid;
  v_application jsonb := p_capture -> 'application';
begin
  perform private.validate_application_capture(p_capture);

  if p_capture ? 'existing_application_id' then
    v_application_id := (p_capture ->> 'existing_application_id')::uuid;
    if not exists (select 1 from public.applications where owner_id = v_owner_id and id = v_application_id) then
      raise exception 'existing application is not owned by the authenticated owner' using errcode = '42501';
    end if;
  else
    if not exists (select 1 from public.companies where owner_id = v_owner_id and id = (v_application ->> 'company_id')::uuid) then
      raise exception 'application company is not owned by the authenticated owner' using errcode = '42501';
    end if;
    if v_application ? 'opportunity_id'
       and not exists (select 1 from public.opportunities where owner_id = v_owner_id and id = (v_application ->> 'opportunity_id')::uuid and company_id = (v_application ->> 'company_id')::uuid) then
      raise exception 'application opportunity is not owned by the authenticated owner or company' using errcode = '42501';
    end if;
    if v_application ? 'job_posting_id'
       and not exists (select 1 from public.job_postings where owner_id = v_owner_id and id = (v_application ->> 'job_posting_id')::uuid and company_id = (v_application ->> 'company_id')::uuid) then
      raise exception 'application job posting is not owned by the authenticated owner or company' using errcode = '42501';
    end if;
    if v_application ? 'submission_snapshot_id'
       and not exists (select 1 from public.job_description_snapshots where owner_id = v_owner_id and id = (v_application ->> 'submission_snapshot_id')::uuid and job_posting_id = (v_application ->> 'job_posting_id')::uuid) then
      raise exception 'application snapshot is not owned by the authenticated owner or job posting' using errcode = '42501';
    end if;
  end if;

  return jsonb_build_object(
    'prepared', true,
    'saved', false,
    'storage_bucket', 'orbit-materials',
    'storage_prefix', v_owner_id::text || '/applications/',
    'materials_count', coalesce(jsonb_array_length(p_capture -> 'materials'), 0)
  );
end;
$$;

create or replace function public.record_application_capture(p_capture jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_application jsonb := p_capture -> 'application';
  v_material jsonb;
  v_application_id uuid;
  v_material_id uuid;
  v_material_version_id uuid;
  v_request_sha256 text;
  v_receipt public.operation_receipts%rowtype;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null then
    raise exception 'operation_key is required' using errcode = '22023';
  end if;
  perform private.validate_application_capture(p_capture);
  v_request_sha256 := encode(extensions.digest(convert_to(p_capture::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_receipt
    from public.operation_receipts
    where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_application_capture' or v_receipt.request_sha256 <> v_request_sha256 then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_application_capture(p_operation_key);
  end if;

  perform public.prepare_application_capture(p_capture);

  if p_capture ? 'existing_application_id' then
    v_application_id := (p_capture ->> 'existing_application_id')::uuid;
  elsif v_application ? 'opportunity_id' then
    select id into v_application_id
      from public.applications
      where owner_id = v_owner_id
        and opportunity_id = (v_application ->> 'opportunity_id')::uuid
      order by submitted_at desc, created_at desc
      limit 1;
  elsif v_application ? 'job_posting_id' then
    select id into v_application_id
      from public.applications
      where owner_id = v_owner_id
        and job_posting_id = (v_application ->> 'job_posting_id')::uuid
      order by submitted_at desc, created_at desc
      limit 1;
  end if;

  if v_application_id is null then
    insert into public.applications (
      owner_id, company_id, opportunity_id, job_posting_id, submission_snapshot_id,
      submitted_at, channel, source_url, source_identifier, submission_evidence,
      missing_snapshot_reason, missing_material_reason
    ) values (
      v_owner_id,
      (v_application ->> 'company_id')::uuid,
      case when v_application ? 'opportunity_id' then (v_application ->> 'opportunity_id')::uuid end,
      case when v_application ? 'job_posting_id' then (v_application ->> 'job_posting_id')::uuid end,
      case when v_application ? 'submission_snapshot_id' then (v_application ->> 'submission_snapshot_id')::uuid end,
      (v_application ->> 'submitted_at')::timestamptz,
      btrim(v_application ->> 'channel'),
      nullif(btrim(coalesce(v_application ->> 'source_url', '')), ''),
      nullif(btrim(coalesce(v_application ->> 'source_identifier', '')), ''),
      nullif(btrim(coalesce(v_application ->> 'submission_evidence', '')), ''),
      nullif(btrim(coalesce(v_application ->> 'missing_snapshot_reason', '')), ''),
      nullif(btrim(coalesce(v_application ->> 'missing_material_reason', '')), '')
    ) returning id into v_application_id;

    insert into public.application_events (
      owner_id, application_id, event_type, occurred_at, note, evidence_url, operation_key
    ) values (
      v_owner_id,
      v_application_id,
      'submitted',
      (v_application ->> 'submitted_at')::timestamptz,
      nullif(btrim(coalesce(v_application ->> 'submission_evidence', '')), ''),
      nullif(btrim(coalesce(v_application ->> 'source_url', '')), ''),
      p_operation_key || ':submitted'
    );
  end if;

  v_result_ids := jsonb_build_array(jsonb_build_object('type', 'application', 'id', v_application_id));

  if p_capture ? 'materials' then
    for v_material in select value from jsonb_array_elements(p_capture -> 'materials')
    loop
      if v_material ? 'material_version_id' then
        v_material_version_id := (v_material ->> 'material_version_id')::uuid;
        if not exists (select 1 from public.material_versions where owner_id = v_owner_id and id = v_material_version_id) then
          raise exception 'material version is not owned by the authenticated owner' using errcode = '42501';
        end if;
      else
        insert into public.materials (owner_id, name, material_type, notes)
        values (
          v_owner_id,
          btrim(v_material ->> 'name'),
          nullif(btrim(coalesce(v_material ->> 'material_type', '')), ''),
          nullif(btrim(coalesce(v_material ->> 'notes', '')), '')
        )
        on conflict (owner_id, normalized_name) do nothing
        returning id into v_material_id;

        if v_material_id is null then
          select id into v_material_id
            from public.materials
            where owner_id = v_owner_id and normalized_name = lower(btrim(v_material ->> 'name'));
        end if;

        insert into public.material_versions (
          owner_id, material_id, version_label, state, external_url, notes,
          territories, approved_at
        ) values (
          v_owner_id,
          v_material_id,
          btrim(v_material ->> 'version_label'),
          coalesce(nullif(btrim(v_material ->> 'state'), ''), 'Listo'),
          nullif(btrim(coalesce(v_material ->> 'external_url', '')), ''),
          nullif(btrim(coalesce(v_material ->> 'notes', '')), ''),
          coalesce(
            array(select jsonb_array_elements_text(v_material -> 'territories')),
            '{}'::text[]
          ),
          nullif(v_material ->> 'approved_at', '')::timestamptz
        )
        on conflict (owner_id, material_id, version_label) do nothing
        returning id into v_material_version_id;

        if v_material_version_id is null then
          select id into v_material_version_id
            from public.material_versions
            where owner_id = v_owner_id
              and material_id = v_material_id
              and version_label = btrim(v_material ->> 'version_label');
        end if;
      end if;

      if v_material ? 'storage_object_path' then
        if split_part(v_material ->> 'storage_object_path', '/', 1) <> v_owner_id::text then
          raise exception 'storage object path must start with authenticated owner ID' using errcode = '42501';
        end if;
        insert into public.material_files (
          owner_id, material_version_id, storage_bucket, storage_object_path,
          original_filename, media_type, byte_size, sha256, source_attachment_id,
          migration_state
        ) values (
          v_owner_id,
          v_material_version_id,
          'orbit-materials',
          btrim(v_material ->> 'storage_object_path'),
          btrim(v_material ->> 'original_filename'),
          coalesce(nullif(btrim(v_material ->> 'media_type'), ''), 'application/pdf'),
          nullif(v_material ->> 'byte_size', '')::bigint,
          nullif(btrim(coalesce(v_material ->> 'sha256', '')), ''),
          nullif(btrim(coalesce(v_material ->> 'source_attachment_id', '')), ''),
          coalesce(nullif(btrim(v_material ->> 'migration_state'), ''), 'pending')
        )
        on conflict (owner_id, storage_bucket, storage_object_path) do nothing;
      end if;

      insert into public.application_material_versions (
        owner_id, application_id, material_version_id, purpose
      ) values (
        v_owner_id,
        v_application_id,
        v_material_version_id,
        coalesce(nullif(btrim(v_material ->> 'purpose'), ''), 'submitted')
      )
      on conflict do nothing;

      v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'material_version', 'id', v_material_version_id));
    end loop;
  end if;

  insert into public.operation_receipts (
    owner_id, operation_key, operation_type, request_sha256, result_record_ids
  ) values (
    v_owner_id,
    p_operation_key,
    'record_application_capture',
    v_request_sha256,
    v_result_ids
  );

  return public.read_back_application_capture(p_operation_key);
end;
$$;

create or replace function public.read_back_application_capture(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_application_id uuid;
begin
  select (entry ->> 'id')::uuid into v_application_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id
     and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'record_application_capture'
     and entry ->> 'type' = 'application';
  if v_application_id is null then
    raise exception 'application capture receipt was not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'saved', true,
    'receipt', (
      select to_jsonb(receipt) - 'owner_id'
      from public.operation_receipts receipt
      where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key
    ),
    'application', (
      select to_jsonb(application) - 'owner_id'
      from public.applications application
      where application.owner_id = v_owner_id and application.id = v_application_id
    ),
    'current_state', (
      select to_jsonb(state) - 'owner_id'
      from public.current_application_states state
      where state.owner_id = v_owner_id and state.application_id = v_application_id
    ),
    'events', coalesce((
      select jsonb_agg(to_jsonb(event) - 'owner_id' order by event.occurred_at, event.id)
      from public.application_events event
      where event.owner_id = v_owner_id and event.application_id = v_application_id
    ), '[]'::jsonb),
    'materials', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'link', to_jsonb(link) - 'owner_id',
          'material_version', to_jsonb(version) - 'owner_id',
          'material', to_jsonb(material) - 'owner_id',
          'files', coalesce((
            select jsonb_agg(to_jsonb(file) - 'owner_id' order by file.created_at, file.id)
            from public.material_files file
            where file.owner_id = v_owner_id and file.material_version_id = version.id
          ), '[]'::jsonb)
        )
        order by link.created_at, version.created_at, version.id
      )
      from public.application_material_versions link
      join public.material_versions version
        on version.owner_id = link.owner_id
       and version.id = link.material_version_id
      join public.materials material
        on material.owner_id = version.owner_id
       and material.id = version.material_id
      where link.owner_id = v_owner_id and link.application_id = v_application_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function private.validate_application_capture(jsonb) from public, anon, authenticated;
revoke all on function public.prepare_application_capture(jsonb) from public, anon, authenticated;
revoke all on function public.record_application_capture(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_application_capture(text) from public, anon, authenticated;

grant execute on function public.prepare_application_capture(jsonb) to authenticated;
grant execute on function public.record_application_capture(jsonb, text) to authenticated;
grant execute on function public.read_back_application_capture(text) to authenticated;

comment on function public.record_application_capture(jsonb, text) is
  'Atomic owner-scoped application capture. Creates or reuses an application, links immutable material versions, registers Storage object metadata, records an idempotency receipt, and reads the authoritative result back.';
