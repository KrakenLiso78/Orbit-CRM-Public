-- A contact may exist before any company, opportunity, or interaction is known.
-- This operation intentionally creates only that contact and its provenance.

create or replace function private.validate_independent_contact(p_contact jsonb)
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
  if jsonb_typeof(p_contact) <> 'object' then
    raise exception 'contact must be a JSON object' using errcode = '22023';
  end if;

  for v_key, v_value in select key, value from jsonb_each(p_contact)
  loop
    if v_key not in (
      'name', 'email', 'phone', 'linkedin_url', 'job_title', 'location',
      'contact_type', 'source_channel', 'relationship_strength',
      'relationship_state', 'priority', 'strategic_value', 'territories',
      'cadence_days', 'last_contact_at', 'next_follow_up_at',
      'personalized_message', 'context_notes', 'source'
    ) then
      raise exception 'unsupported independent contact field: %', v_key using errcode = '22023';
    end if;
    if v_key = 'territories' then
      if jsonb_typeof(v_value) <> 'array' or exists (
        select 1 from jsonb_array_elements(v_value) as element(value)
        where jsonb_typeof(element.value) <> 'string'
      ) then
        raise exception 'territories must be an array of strings' using errcode = '22023';
      end if;
    elsif v_key = 'cadence_days' then
      if jsonb_typeof(v_value) not in ('number', 'null') then
        raise exception 'cadence_days must be a number or null' using errcode = '22023';
      end if;
    elsif v_key <> 'source' and jsonb_typeof(v_value) not in ('string', 'null') then
      raise exception 'contact field % must be a string or null', v_key using errcode = '22023';
    end if;
  end loop;

  if jsonb_typeof(p_contact -> 'name') <> 'string'
     or nullif(btrim(p_contact ->> 'name'), '') is null then
    raise exception 'contact name is required' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_contact ->> 'email', '')), '') is null
     and nullif(btrim(coalesce(p_contact ->> 'linkedin_url', '')), '') is null then
    raise exception 'contact email or LinkedIn URL is required for independent creation' using errcode = '22023';
  end if;
  if p_contact ? 'cadence_days' and p_contact ->> 'cadence_days' is not null then
    perform (p_contact ->> 'cadence_days')::smallint;
  end if;
  if p_contact ? 'last_contact_at' and p_contact ->> 'last_contact_at' is not null then
    perform (p_contact ->> 'last_contact_at')::timestamptz;
  end if;
  if p_contact ? 'next_follow_up_at' and p_contact ->> 'next_follow_up_at' is not null then
    perform (p_contact ->> 'next_follow_up_at')::timestamptz;
  end if;

  v_source := p_contact -> 'source';
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
     or nullif(btrim(v_source ->> 'source_record_id'), '') is null then
    raise exception 'contact source_system, source_database, and source_record_id are required' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_each(v_source) as entry(key, value)
    where jsonb_typeof(entry.value) not in ('string', 'null')
  ) then
    raise exception 'contact source fields must be strings or null' using errcode = '22023';
  end if;
  if v_source ? 'source_created_at' then perform (v_source ->> 'source_created_at')::timestamptz; end if;
  if v_source ? 'source_updated_at' then perform (v_source ->> 'source_updated_at')::timestamptz; end if;
  if v_source ? 'source_sha256' and (v_source ->> 'source_sha256' !~ '^[0-9a-f]{64}$') then
    raise exception 'source_sha256 must be a lowercase SHA-256 hexadecimal digest' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.create_independent_contact(p_contact jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_source jsonb := p_contact -> 'source';
  v_request_sha256 text;
  v_receipt public.operation_receipts%rowtype;
  v_contact_id uuid;
  v_source_record_id uuid;
begin
  if nullif(btrim(p_operation_key), '') is null then
    raise exception 'operation_key is required' using errcode = '22023';
  end if;
  perform private.validate_independent_contact(p_contact);
  v_request_sha256 := encode(extensions.digest(convert_to(p_contact::text, 'UTF8'), 'sha256'), 'hex');

  select * into v_receipt
    from public.operation_receipts
   where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'create_independent_contact'
       or v_receipt.request_sha256 <> v_request_sha256 then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_independent_contact(p_operation_key);
  end if;

  if exists (
    select 1 from public.contacts
     where owner_id = v_owner_id
       and (
         (nullif(btrim(coalesce(p_contact ->> 'email', '')), '') is not null
          and lower(btrim(email)) = lower(btrim(p_contact ->> 'email')))
         or (nullif(btrim(coalesce(p_contact ->> 'linkedin_url', '')), '') is not null
          and lower(btrim(linkedin_url)) = lower(btrim(p_contact ->> 'linkedin_url')))
       )
  ) then
    raise exception 'contact identity already exists; resolve it before correcting or relating it' using errcode = '23505';
  end if;
  if exists (
    select 1 from public.source_records
     where owner_id = v_owner_id
       and source_system = btrim(v_source ->> 'source_system')
       and source_database = btrim(v_source ->> 'source_database')
       and source_record_id = btrim(v_source ->> 'source_record_id')
  ) then
    raise exception 'contact source is already mapped; resolve it before creating a new contact' using errcode = '23505';
  end if;

  insert into public.contacts (
    owner_id, name, email, phone, linkedin_url, job_title, location, contact_type,
    source_channel, relationship_strength, relationship_state, priority,
    strategic_value, territories, cadence_days, last_contact_at, next_follow_up_at,
    personalized_message, context_notes
  ) values (
    v_owner_id, btrim(p_contact ->> 'name'),
    nullif(btrim(coalesce(p_contact ->> 'email', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'phone', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'linkedin_url', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'job_title', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'location', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'contact_type', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'source_channel', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'relationship_strength', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'relationship_state', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'priority', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'strategic_value', '')), ''),
    case when p_contact ? 'territories' then array(select jsonb_array_elements_text(p_contact -> 'territories')) else '{}'::text[] end,
    case when p_contact ? 'cadence_days' then (p_contact ->> 'cadence_days')::smallint end,
    case when p_contact ? 'last_contact_at' then (p_contact ->> 'last_contact_at')::timestamptz end,
    case when p_contact ? 'next_follow_up_at' then (p_contact ->> 'next_follow_up_at')::timestamptz end,
    nullif(btrim(coalesce(p_contact ->> 'personalized_message', '')), ''),
    nullif(btrim(coalesce(p_contact ->> 'context_notes', '')), '')
  ) returning id into v_contact_id;

  insert into public.source_records (
    owner_id, source_system, source_database, source_record_id, source_url,
    source_created_at, source_updated_at, source_sha256, reconciliation_state,
    contact_id
  ) values (
    v_owner_id, btrim(v_source ->> 'source_system'), btrim(v_source ->> 'source_database'),
    btrim(v_source ->> 'source_record_id'), nullif(btrim(coalesce(v_source ->> 'source_url', '')), ''),
    nullif(v_source ->> 'source_created_at', '')::timestamptz,
    nullif(v_source ->> 'source_updated_at', '')::timestamptz,
    nullif(btrim(coalesce(v_source ->> 'source_sha256', '')), ''), 'mapped', v_contact_id
  ) returning id into v_source_record_id;

  insert into public.operation_receipts (owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (
    v_owner_id, p_operation_key, 'create_independent_contact', v_request_sha256,
    jsonb_build_array(
      jsonb_build_object('type', 'contact', 'id', v_contact_id),
      jsonb_build_object('type', 'source_record', 'id', v_source_record_id)
    )
  );

  return public.read_back_independent_contact(p_operation_key);
end;
$$;

create or replace function public.read_back_independent_contact(p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_contact_id uuid;
  v_source_record_id uuid;
begin
  select (entry ->> 'id')::uuid into v_contact_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id
     and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'create_independent_contact'
     and entry ->> 'type' = 'contact';
  select (entry ->> 'id')::uuid into v_source_record_id
    from public.operation_receipts receipt
    cross join lateral jsonb_array_elements(receipt.result_record_ids) as entry
   where receipt.owner_id = v_owner_id
     and receipt.operation_key = p_operation_key
     and receipt.operation_type = 'create_independent_contact'
     and entry ->> 'type' = 'source_record';
  if v_contact_id is null or v_source_record_id is null then
    raise exception 'independent contact receipt was not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'saved', true,
    'receipt', (select to_jsonb(receipt) - 'owner_id' from public.operation_receipts receipt where receipt.owner_id = v_owner_id and receipt.operation_key = p_operation_key),
    'contact', (select to_jsonb(contact) - 'owner_id' from public.contacts contact where contact.owner_id = v_owner_id and contact.id = v_contact_id),
    'source_record', (select to_jsonb(source) - 'owner_id' from public.source_records source where source.owner_id = v_owner_id and source.id = v_source_record_id),
    'affiliations', '[]'::jsonb,
    'interactions', '[]'::jsonb
  );
end;
$$;

revoke all on function private.validate_independent_contact(jsonb) from public, anon, authenticated;
revoke all on function public.create_independent_contact(jsonb, text) from public, anon, authenticated;
revoke all on function public.read_back_independent_contact(text) from public, anon, authenticated;
grant execute on function public.create_independent_contact(jsonb, text) to authenticated;
grant execute on function public.read_back_independent_contact(text) to authenticated;

comment on function public.create_independent_contact(jsonb, text) is
  'Creates exactly one independent owner contact with stable identity, source provenance, idempotency, and authoritative readback; it creates no affiliation, opportunity, interaction, or task.';
