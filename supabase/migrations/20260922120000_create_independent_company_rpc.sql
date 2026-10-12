-- A company may exist before a contact, opportunity, or interaction is known.
-- This operation intentionally creates only that company and its provenance.

create or replace function private.validate_independent_company(p_company jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_value jsonb;
  v_source jsonb;
begin
  if jsonb_typeof(p_company) <> 'object' then
    raise exception 'company must be a JSON object' using errcode = '22023';
  end if;

  for v_key, v_value in select key, value from jsonb_each(p_company)
  loop
    if v_key not in (
      'name', 'website_url', 'linkedin_url', 'careers_url', 'headquarters',
      'size_band', 'priority', 'strategic_fit', 'fit_reason', 'notes',
      'segments', 'markets', 'source'
    ) then
      raise exception 'unsupported independent company field: %', v_key using errcode = '22023';
    end if;
    if v_key in ('segments', 'markets') then
      if jsonb_typeof(v_value) <> 'array' or exists (
        select 1 from jsonb_array_elements(v_value) as element(value)
        where jsonb_typeof(element.value) <> 'string'
      ) then
        raise exception 'company field % must be an array of strings', v_key using errcode = '22023';
      end if;
    elsif v_key <> 'source' and jsonb_typeof(v_value) not in ('string', 'null') then
      raise exception 'company field % must be a string or null', v_key using errcode = '22023';
    end if;
  end loop;

  if jsonb_typeof(p_company -> 'name') <> 'string'
     or nullif(btrim(p_company ->> 'name'), '') is null then
    raise exception 'company name is required' using errcode = '22023';
  end if;

  v_source := p_company -> 'source';
  if jsonb_typeof(v_source) <> 'object'
     or exists (
       select 1 from jsonb_object_keys(v_source) as key
       where key not in ('source_system', 'source_database', 'source_record_id', 'source_url', 'source_created_at', 'source_updated_at', 'source_sha256')
     )
     or jsonb_typeof(v_source -> 'source_system') <> 'string'
     or jsonb_typeof(v_source -> 'source_database') <> 'string'
     or jsonb_typeof(v_source -> 'source_record_id') <> 'string'
     or nullif(btrim(v_source ->> 'source_system'), '') is null
     or nullif(btrim(v_source ->> 'source_database'), '') is null
     or nullif(btrim(v_source ->> 'source_record_id'), '') is null
     or exists (
       select 1 from jsonb_each(v_source) as entry(key, value)
       where jsonb_typeof(entry.value) not in ('string', 'null')
     ) then
    raise exception 'company source_system, source_database, and source_record_id are required strings' using errcode = '22023';
  end if;
  if v_source ? 'source_created_at' then perform (v_source ->> 'source_created_at')::timestamptz; end if;
  if v_source ? 'source_updated_at' then perform (v_source ->> 'source_updated_at')::timestamptz; end if;
  if v_source ? 'source_sha256' and (v_source ->> 'source_sha256' !~ '^[0-9a-f]{64}$') then
    raise exception 'source_sha256 must be a lowercase SHA-256 hexadecimal digest' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.create_independent_company(p_company jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_source jsonb := p_company -> 'source';
  v_request_sha256 text;
  v_receipt public.operation_receipts%rowtype;
  v_company_id uuid;
  v_source_record_id uuid;
begin
  if nullif(btrim(p_operation_key), '') is null then
    raise exception 'operation_key is required' using errcode = '22023';
  end if;
  perform private.validate_independent_company(p_company);
  v_request_sha256 := encode(extensions.digest(convert_to(p_company::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_receipt
    from public.operation_receipts
   where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'create_independent_company'
       or v_receipt.request_sha256 <> v_request_sha256 then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_independent_company(p_operation_key);
  end if;

  if exists (
    select 1 from public.companies
     where owner_id = v_owner_id
       and (
         normalized_name = lower(btrim(p_company ->> 'name'))
         or (nullif(btrim(coalesce(p_company ->> 'website_url', '')), '') is not null
             and lower(btrim(website_url)) = lower(btrim(p_company ->> 'website_url')))
         or (nullif(btrim(coalesce(p_company ->> 'linkedin_url', '')), '') is not null
             and lower(btrim(linkedin_url)) = lower(btrim(p_company ->> 'linkedin_url')))
       )
  ) then
    raise exception 'company identity already exists; resolve it before correcting or relating it' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.source_records
     where owner_id = v_owner_id
       and source_system = btrim(v_source ->> 'source_system')
       and source_database = btrim(v_source ->> 'source_database')
       and source_record_id = btrim(v_source ->> 'source_record_id')
  ) then
    raise exception 'company source is already mapped; resolve it before creating a new company' using errcode = '23505';
  end if;

  insert into public.companies (
    owner_id, name, website_url, linkedin_url, careers_url, headquarters,
    size_band, priority, strategic_fit, fit_reason, notes, segments, markets
  ) values (
    v_owner_id, btrim(p_company ->> 'name'),
    nullif(btrim(coalesce(p_company ->> 'website_url', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'linkedin_url', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'careers_url', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'headquarters', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'size_band', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'priority', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'strategic_fit', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'fit_reason', '')), ''),
    nullif(btrim(coalesce(p_company ->> 'notes', '')), ''),
    case when p_company ? 'segments' then array(select jsonb_array_elements_text(p_company -> 'segments')) else '{}'::text[] end,
    case when p_company ? 'markets' then array(select jsonb_array_elements_text(p_company -> 'markets')) else '{}'::text[] end
  ) returning id into v_company_id;

  insert into public.source_records (
    owner_id, source_system, source_database, source_record_id, source_url,
    source_created_at, source_updated_at, source_sha256, reconciliation_state,
    company_id
  ) values (
    v_owner_id, btrim(v_source ->> 'source_system'), btrim(v_source ->> 'source_database'),
    btrim(v_source ->> 'source_record_id'), nullif(btrim(coalesce(v_source ->> 'source_url', '')), ''),
    nullif(v_source ->> 'source_created_at', '')::timestamptz,
    nullif(v_source ->> 'source_updated_at', '')::timestamptz,
    nullif(btrim(coalesce(v_source ->> 'source_sha256', '')), ''), 'mapped', v_company_id
  ) returning id into v_source_record_id;

  insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (
    v_owner_id, p_operation_key, 'create_independent_company', v_request_sha256,
    jsonb_build_array(
      jsonb_build_object('type', 'company', 'id', v_company_id),
      jsonb_build_object('type', 'source_record', 'id', v_source_record_id)
    )
  );

  return public.read_back_independent_company(p_operation_key);
end;
$$;

create or replace function public.read_back_independent_company(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_company_id uuid;
  v_source_record_id uuid;
begin
  select (entry ->> 'id')::uuid into v_company_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id
     and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'create_independent_company'
     and entry ->> 'type' = 'company';
  select (entry ->> 'id')::uuid into v_source_record_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id
     and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'create_independent_company'
     and entry ->> 'type' = 'source_record';
  if v_company_id is null or v_source_record_id is null then
    raise exception 'independent company receipt was not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'saved', true,
    'receipt', (select to_jsonb(receipt) - 'owner_id' from public.operation_receipts receipt where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key),
    'company', (select to_jsonb(company) - 'owner_id' from public.companies company where company.owner_id = v_owner_id and company.id = v_company_id),
    'source_record', (select to_jsonb(source) - 'owner_id' from public.source_records source where source.owner_id = v_owner_id and source.id = v_source_record_id),
    'contacts', '[]'::jsonb,
    'opportunities', '[]'::jsonb,
    'interactions', '[]'::jsonb
  );
end;
$$;

revoke all on function private.validate_independent_company(jsonb) from public, anon, authenticated;
revoke all on function public.create_independent_company(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_independent_company(text) from public, anon, authenticated;
grant execute on function public.create_independent_company(jsonb, text) to authenticated;
grant execute on function public.read_back_independent_company(text) to authenticated;

comment on function public.create_independent_company(jsonb, text) is
  'Creates exactly one independent owner company with source provenance, idempotency, and authoritative readback; it creates no contact, opportunity, interaction, or task.';
