-- Link market-review signals to the execution that produced them so the portal
-- does not mix general CRM signals with governed pharmaceutical-review output.
create table if not exists public.market_review_signal_links (
  owner_id uuid not null references public.crm_owner_profiles(owner_id) on delete cascade,
  monitor_execution_id uuid not null,
  market_signal_id uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (owner_id, monitor_execution_id, market_signal_id),
  foreign key (owner_id, monitor_execution_id) references public.monitor_executions(owner_id, id) on delete cascade,
  foreign key (owner_id, market_signal_id) references public.market_signals(owner_id, id) on delete restrict
);
alter table public.market_review_signal_links enable row level security;
alter table public.market_review_signal_links force row level security;
drop policy if exists market_review_signal_links_owner_select on public.market_review_signal_links;
create policy market_review_signal_links_owner_select on public.market_review_signal_links
  for select to authenticated using ((select auth.uid()) = owner_id);
revoke all on public.market_review_signal_links from public, anon, authenticated;
grant select on public.market_review_signal_links to authenticated;

insert into public.market_review_signal_links(owner_id, monitor_execution_id, market_signal_id)
select receipt.owner_id,
  (select (entry ->> 'id')::uuid from jsonb_array_elements(receipt.result_record_ids) entry where entry ->> 'type' = 'monitor_execution' limit 1),
  (signal_entry ->> 'id')::uuid
from public.operation_receipts receipt
cross join lateral jsonb_array_elements(receipt.result_record_ids) signal_entry
where receipt.operation_type = 'record_market_review_run'
  and signal_entry ->> 'type' = 'market_signal'
on conflict do nothing;

create or replace function public.record_market_review_run(p_run jsonb, p_operation_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid := private.require_call_report_owner();
  v_hash text;
  v_receipt public.operation_receipts%rowtype;
  v_execution_id uuid;
  v_signal jsonb;
  v_signal_id uuid;
  v_notification_id uuid;
  v_result_ids jsonb := '[]'::jsonb;
begin
  if nullif(btrim(p_operation_key), '') is null or jsonb_typeof(p_run) <> 'object'
     or jsonb_typeof(p_run -> 'signals') <> 'array'
     or (p_run ->> 'status') not in ('succeeded', 'partial', 'failed') then
    raise exception 'run requires operation_key, status, and a signals array' using errcode = '22023';
  end if;
  v_hash := encode(extensions.digest(convert_to(p_run::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from public.operation_receipts where owner_id = v_owner_id and operation_key = p_operation_key;
  if found then
    if v_receipt.operation_type <> 'record_market_review_run' or v_receipt.request_sha256 <> v_hash then
      raise exception 'operation_key was already used with a different request' using errcode = '23505';
    end if;
    return public.read_back_market_review_run(p_operation_key);
  end if;
  insert into public.monitor_executions(owner_id, monitor_type, execution_key, started_at, completed_at, status, scope, summary, failures, scheduler, dependency_note)
  values (v_owner_id, 'market_review', p_run ->> 'execution_key', (p_run ->> 'started_at')::timestamptz,
    (p_run ->> 'completed_at')::timestamptz, p_run ->> 'status', coalesce(p_run -> 'scope', '{}'::jsonb),
    coalesce(p_run -> 'summary', '{}'::jsonb), coalesce(p_run -> 'failures', '[]'::jsonb),
    coalesce(nullif(p_run ->> 'scheduler', ''), 'manual'), nullif(p_run ->> 'dependency_note', ''))
  returning id into v_execution_id;
  v_result_ids := jsonb_build_array(jsonb_build_object('type', 'monitor_execution', 'id', v_execution_id));
  for v_signal in select value from jsonb_array_elements(p_run -> 'signals')
  loop
    if nullif(btrim(v_signal ->> 'title'), '') is null or coalesce(v_signal ->> 'source_url', '') !~ '^https://'
       or nullif(v_signal ->> 'signal_date', '') is null then
      raise exception 'each signal requires title, date, and an https source URL' using errcode = '22023';
    end if;
    insert into public.market_signals(owner_id, title, signal_type, signal_date, source_url, relevance, state,
      search_implication, suggested_action, notes)
    values (v_owner_id, btrim(v_signal ->> 'title'), nullif(v_signal ->> 'signal_type', ''),
      (v_signal ->> 'signal_date')::date, btrim(v_signal ->> 'source_url'),
      coalesce(nullif(v_signal ->> 'relevance', ''), 'Media'), 'Nueva',
      nullif(v_signal ->> 'search_implication', ''), nullif(v_signal ->> 'suggested_action', ''),
      nullif(v_signal ->> 'notes', '')) returning id into v_signal_id;
    insert into public.market_review_signal_links(owner_id, monitor_execution_id, market_signal_id)
    values (v_owner_id, v_execution_id, v_signal_id);
    v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'market_signal', 'id', v_signal_id));
  end loop;
  insert into public.private_notifications(owner_id, notification_key, notification_type, title, body)
  values (v_owner_id, concat('market:', p_run ->> 'execution_key'), 'market_review',
    coalesce(nullif(p_run ->> 'title', ''), 'Market review'),
    jsonb_build_object('execution_id', v_execution_id, 'signal_count', jsonb_array_length(p_run -> 'signals'), 'status', p_run ->> 'status'))
  returning id into v_notification_id;
  v_result_ids := v_result_ids || jsonb_build_array(jsonb_build_object('type', 'private_notification', 'id', v_notification_id));
  insert into public.operation_receipts(owner_id, operation_key, operation_type, request_sha256, result_record_ids)
  values (v_owner_id, p_operation_key, 'record_market_review_run', v_hash, v_result_ids);
  return public.read_back_market_review_run(p_operation_key);
end;
$$;

create or replace function public.get_orbit_mvp_snapshot(p_limit integer default 12)
returns jsonb
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'generated_at', timezone('utc', now()),
    'job_roles', coalesce((select jsonb_agg(to_jsonb(x) order by x.score desc nulls last, x.last_seen_at desc)
      from (select j.id, j.title, c.name company_name, j.location, j.work_arrangement, j.source_url,
        j.status, j.first_seen_at, j.last_seen_at, j.posted_at, j.closing_at,
        a.score, a.confidence, a.rationale, a.strengths, a.gaps, a.constraints, a.assessed_at
        from public.job_postings j join public.companies c on c.owner_id = j.owner_id and c.id = j.company_id
        join lateral (select fa.* from public.fit_assessments fa where fa.owner_id = j.owner_id and fa.job_posting_id = j.id order by fa.assessed_at desc limit 1) a on true
        where j.owner_id = (select auth.uid()) and j.status = 'open'
        order by a.score desc nulls last, j.last_seen_at desc limit greatest(1, least(coalesce(p_limit, 12), 50))) x), '[]'::jsonb),
    'market_signals', coalesce((select jsonb_agg(to_jsonb(x) order by x.signal_date desc, x.created_at desc)
      from (select s.id, s.title, s.signal_type, s.signal_date, s.source_url, s.relevance, s.state, s.search_implication, s.suggested_action, s.notes, s.created_at
        from public.market_signals s join public.market_review_signal_links l
          on l.owner_id = s.owner_id and l.market_signal_id = s.id
        where s.owner_id = (select auth.uid()) and s.state <> 'Archivada'
        order by signal_date desc, created_at desc limit greatest(1, least(coalesce(p_limit, 12), 50))) x), '[]'::jsonb),
    'executions', coalesce((select jsonb_agg(to_jsonb(x) order by x.started_at desc)
      from (select id, monitor_type, execution_key, started_at, completed_at, status, scope, summary, failures, scheduler, dependency_note
        from public.monitor_executions where owner_id = (select auth.uid()) order by started_at desc limit 10) x), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (select id, notification_type, title, body, state, created_at from public.private_notifications
        where owner_id = (select auth.uid()) and state = 'unread' order by created_at desc limit 20) x), '[]'::jsonb)
  );
$$;

