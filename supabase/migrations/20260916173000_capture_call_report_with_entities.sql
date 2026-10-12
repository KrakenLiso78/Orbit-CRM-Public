-- Explicit, narrow Call Report capture: entity creation is only possible as
-- part of one owner-scoped interaction capture, never as generic CRUD.
create or replace function public.capture_call_report_with_entities(p_capture jsonb, p_operation_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_company jsonb := p_capture -> 'company';
  v_contact jsonb := p_capture -> 'contact';
  v_opportunity jsonb := p_capture -> 'opportunity';
  v_company_row public.companies%rowtype;
  v_contact_row public.contacts%rowtype;
  v_opportunity_row public.opportunities%rowtype;
  v_interaction jsonb;
begin
  if jsonb_typeof(p_capture) <> 'object' or jsonb_typeof(v_company) <> 'object' or jsonb_typeof(v_contact) <> 'object' or jsonb_typeof(v_opportunity) <> 'object' or nullif(btrim(p_operation_key), '') is null then
    raise exception 'Call Report entity capture requires company, contact, opportunity, and operation key' using errcode = '22023';
  end if;
  if nullif(btrim(v_company ->> 'name'), '') is null or nullif(btrim(v_contact ->> 'name'), '') is null or nullif(btrim(v_contact ->> 'linkedin_url'), '') is null or nullif(btrim(v_opportunity ->> 'title'), '') is null then
    raise exception 'Call Report entity identity is incomplete' using errcode = '22023';
  end if;
  select * into v_company_row from public.companies where owner_id = v_owner_id and normalized_name = lower(btrim(v_company ->> 'name')) order by archived_at nulls first, created_at limit 1;
  if not found then
    insert into public.companies(owner_id, name, website_url, linkedin_url, careers_url, notes)
    values(v_owner_id, btrim(v_company ->> 'name'), nullif(btrim(v_company ->> 'website_url'), ''), nullif(btrim(v_company ->> 'linkedin_url'), ''), nullif(btrim(v_company ->> 'careers_url'), ''), nullif(btrim(v_company ->> 'notes'), '')) returning * into v_company_row;
  end if;
  select * into v_contact_row from public.contacts where owner_id = v_owner_id and lower(linkedin_url) = lower(btrim(v_contact ->> 'linkedin_url')) order by archived_at nulls first, created_at limit 1;
  if not found then
    insert into public.contacts(owner_id, name, email, linkedin_url, job_title, source_channel, context_notes, last_contact_at)
    values(v_owner_id, btrim(v_contact ->> 'name'), nullif(btrim(v_contact ->> 'email'), ''), btrim(v_contact ->> 'linkedin_url'), nullif(btrim(v_contact ->> 'job_title'), ''), 'LinkedIn', nullif(btrim(v_contact ->> 'context_notes'), ''), timezone('utc', now())) returning * into v_contact_row;
  end if;
  insert into public.contact_company_affiliations(owner_id, contact_id, company_id, relationship_type, current_state)
  values(v_owner_id, v_contact_row.id, v_company_row.id, 'professional contact', 'unknown') on conflict do nothing;
  select * into v_opportunity_row from public.opportunities where owner_id = v_owner_id and company_id = v_company_row.id and lower(btrim(title)) = lower(btrim(v_opportunity ->> 'title')) order by archived_at nulls first, created_at limit 1;
  if not found then
    insert into public.opportunities(owner_id, company_id, title, status, source_type, opened_on, target_role, location, work_mode, notes)
    values(v_owner_id, v_company_row.id, btrim(v_opportunity ->> 'title'), 'Open', 'direct outreach', coalesce(nullif(v_opportunity ->> 'opened_on', '')::date, current_date), nullif(btrim(v_opportunity ->> 'target_role'), ''), nullif(btrim(v_opportunity ->> 'location'), ''), coalesce(nullif(btrim(v_opportunity ->> 'work_mode'), ''), 'Remoto'), concat_ws(E'\n', nullif(btrim(v_opportunity ->> 'notes'), ''), case when nullif(btrim(v_opportunity ->> 'source_url'), '') is not null then 'Source URL: ' || btrim(v_opportunity ->> 'source_url') end)) returning * into v_opportunity_row;
  end if;
  insert into public.opportunity_contacts(owner_id, opportunity_id, contact_id, role)
  values(v_owner_id, v_opportunity_row.id, v_contact_row.id, 'recruiter') on conflict do nothing;
  v_interaction := p_capture - 'company' - 'contact' - 'opportunity';
  v_interaction := jsonb_set(v_interaction, '{contact_ids}', jsonb_build_array(to_jsonb(v_contact_row.id)), true);
  v_interaction := jsonb_set(v_interaction, '{context}', jsonb_build_object('opportunity_id', v_opportunity_row.id), true);
  return public.record_interaction_capture(v_interaction, p_operation_key);
end;
$$;
revoke all on function public.capture_call_report_with_entities(jsonb, text) from public, anon, authenticated;
grant execute on function public.capture_call_report_with_entities(jsonb, text) to authenticated;
