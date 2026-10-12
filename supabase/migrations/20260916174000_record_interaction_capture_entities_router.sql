-- Keep the already exposed Call Report RPC usable in this session while
-- routing the explicitly authorised nested-entity capture to its atomic path.
alter function public.record_interaction_capture(jsonb, text)
  rename to record_interaction_capture_core;

create or replace function public.record_interaction_capture(p_capture jsonb, p_operation_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_capture ? 'company' or p_capture ? 'contact' or p_capture ? 'opportunity' then
    return public.capture_call_report_with_entities(p_capture, p_operation_key);
  end if;
  return public.record_interaction_capture_core(p_capture, p_operation_key);
end;
$$;

revoke all on function public.record_interaction_capture(jsonb, text) from public, anon, authenticated;
grant execute on function public.record_interaction_capture(jsonb, text) to authenticated;
