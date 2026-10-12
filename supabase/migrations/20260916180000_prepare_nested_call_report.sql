-- Preparation must understand the same explicit nested entity envelope while
-- remaining read-only. It never creates or mutates records.
alter function public.prepare_interaction_capture(jsonb)
  rename to prepare_interaction_capture_core;

create or replace function public.prepare_interaction_capture(p_capture jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_capture ? 'company' or p_capture ? 'contact' or p_capture ? 'opportunity' then
    if jsonb_typeof(p_capture -> 'company') <> 'object' or jsonb_typeof(p_capture -> 'contact') <> 'object' or jsonb_typeof(p_capture -> 'opportunity') <> 'object' then
      raise exception 'nested Call Report entities must be objects' using errcode = '22023';
    end if;
    if nullif(btrim(p_capture -> 'company' ->> 'name'), '') is null or nullif(btrim(p_capture -> 'contact' ->> 'name'), '') is null or nullif(btrim(p_capture -> 'contact' ->> 'linkedin_url'), '') is null or nullif(btrim(p_capture -> 'opportunity' ->> 'title'), '') is null then
      raise exception 'nested Call Report entity identity is incomplete' using errcode = '22023';
    end if;
    return jsonb_build_object('prepared', true, 'saved', false, 'nested_entities', true);
  end if;
  return public.prepare_interaction_capture_core(p_capture);
end;
$$;
revoke all on function public.prepare_interaction_capture(jsonb) from public, anon, authenticated;
grant execute on function public.prepare_interaction_capture(jsonb) to authenticated;
