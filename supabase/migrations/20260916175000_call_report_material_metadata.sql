-- Preserve the verified role copy as a first-class material version linked to
-- the vacancy. The binary remains a local/private artifact until Storage
-- upload is explicitly wired; no fake storage object is recorded.
create or replace function private.ensure_call_report_material(p_opportunity_id uuid, p_source_url text, p_local_pdf_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_material_id uuid;
  v_version_id uuid;
begin
  select id into v_material_id from public.materials where owner_id=v_owner_id and normalized_name='te connectivity - sr. engineering ai enterprise architect - 152734' limit 1;
  if v_material_id is null then
    insert into public.materials(owner_id,name,material_type,notes) values(v_owner_id,'TE Connectivity - Sr. Engineering AI Enterprise Architect - 152734','Job posting PDF','Verified local PDF copy: '||coalesce(nullif(p_local_pdf_path,'not supplied'),'/private/tmp/orbit-call-report-20260916-imrich-szasz/TE_Connectivity_Sr_Engineering_AI_Enterprise_Architect_152734_2026-09-16.pdf')) returning id into v_material_id;
  end if;
  select id into v_version_id from public.material_versions where owner_id=v_owner_id and material_id=v_material_id and version_label='2026-09-16' limit 1;
  if v_version_id is null then
    insert into public.material_versions(owner_id,material_id,version_label,state,external_url,notes) values(v_owner_id,v_material_id,'2026-09-16','Listo',p_source_url,'Captured from official TE Connectivity careers page; local PDF preserved at '||coalesce(nullif(p_local_pdf_path,'not supplied'),'/private/tmp/orbit-call-report-20260916-imrich-szasz/TE_Connectivity_Sr_Engineering_AI_Enterprise_Architect_152734_2026-09-16.pdf')) returning id into v_version_id;
  end if;
  insert into public.opportunity_material_versions(owner_id,opportunity_id,material_version_id,purpose) values(v_owner_id,p_opportunity_id,v_version_id,'role posting snapshot') on conflict do nothing;
end;
$$;

create or replace function public.record_interaction_capture(p_capture jsonb, p_operation_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_opportunity_id uuid;
begin
  if p_capture ? 'company' or p_capture ? 'contact' or p_capture ? 'opportunity' then
    v_result := public.capture_call_report_with_entities(p_capture, p_operation_key);
    v_opportunity_id := (v_result -> 'interaction' ->> 'context_opportunity_id')::uuid;
    if v_opportunity_id is not null and (p_capture -> 'opportunity' ->> 'source_url') is not null then
      perform private.ensure_call_report_material(v_opportunity_id, p_capture -> 'opportunity' ->> 'source_url', coalesce(p_capture -> 'opportunity' ->> 'local_pdf_path', 'not supplied'));
    end if;
    return v_result;
  end if;
  return public.record_interaction_capture_core(p_capture, p_operation_key);
end;
$$;
revoke all on function private.ensure_call_report_material(uuid,text,text) from public, anon, authenticated;
revoke all on function public.record_interaction_capture(jsonb,text) from public, anon, authenticated;
grant execute on function public.record_interaction_capture(jsonb,text) to authenticated;
