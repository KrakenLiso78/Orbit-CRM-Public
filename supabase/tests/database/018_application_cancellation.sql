-- FR-060 cancellation is an explicit employer outcome, not vacancy inference.
begin;
do $$
declare own uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); j uuid:=gen_random_uuid(); latest uuid; payload jsonb; r jsonb;
begin
 insert into auth.users(id,aud,role) values(own,'authenticated','authenticated');
 insert into public.crm_owner_profiles(owner_id) values(own);
 insert into public.companies(id,owner_id,name) values(c,own,'Synthetic cancellation');
 insert into public.job_postings(id,owner_id,company_id,title,source_url,status,first_seen_at,last_seen_at) values(j,own,c,'Synthetic vacancy','https://example.invalid/job','open',now(),now());
 insert into public.applications(id,owner_id,company_id,job_posting_id,submitted_at,channel,submission_evidence,missing_snapshot_reason) values(a,own,c,j,now()-interval '5 days','synthetic','Synthetic submission','Synthetic fixture without snapshot');
 insert into public.application_events(owner_id,application_id,event_type,occurred_at,note,operation_key) values(own,a,'submitted',now()-interval '5 days','Synthetic submission','cancel-fixture-submit') returning id into latest;
 update public.job_postings set status='closed' where id=j;
 perform set_config('request.jwt.claim.sub',own::text,true);
 execute 'set local role authenticated';
 if (public.get_application_register()->0->>'current_state')<>'submitted' then raise exception 'Vacancy closure inferred outcome'; end if;
 payload:=jsonb_build_object('application_id',a,'expected_latest_event_id',latest,'event_type','cancelled','occurred_at',now()-interval '2 days','note','Employer explicitly cancelled the process');
 r:=public.record_application_event(payload,'cancel-fixture-event');
 if public.record_application_event(payload,'cancel-fixture-event')<>r then raise exception 'Exact replay failed'; end if;
 if (public.get_application_register()->0->>'current_state')<>'cancelled' then raise exception 'Cancelled register state missing'; end if;
 if jsonb_array_length(public.get_dashboard_snapshot()->'recent_applications')<>0 then raise exception 'Cancelled dashboard card retained'; end if;
 if (public.get_dashboard_snapshot()#>>'{counts,applications}')::int<>1 then raise exception 'KPI changed'; end if;
 select id into latest from public.application_events where application_id=a order by created_at desc,id desc limit 1;
 perform public.record_application_event(jsonb_build_object('application_id',a,'expected_latest_event_id',latest,'event_type','follow_up','occurred_at',now()-interval '1 day','note','Later explanatory note'),'cancel-fixture-note');
 if (public.get_application_register()->0->>'current_state')<>'cancelled' then raise exception 'Note replaced cancellation'; end if;
 select id into latest from public.application_events where application_id=a order by created_at desc,id desc limit 1;
 begin
  perform public.record_application_event(jsonb_build_object('application_id',a,'expected_latest_event_id',latest,'event_type','interview','occurred_at',now()-interval '1 hour','note','Attempt without reopening'),'cancel-fixture-invalid');
  raise exception 'Closed application progressed';
 exception when invalid_parameter_value then null; end;
 perform public.record_application_event(jsonb_build_object('application_id',a,'expected_latest_event_id',latest,'event_type','reopened','occurred_at',now()-interval '1 hour','note','Explicit employer reopening'),'cancel-fixture-reopen');
 if jsonb_array_length(public.get_dashboard_snapshot()->'recent_applications')<>1 then raise exception 'Reopened card missing'; end if;
 if (select count(*) from public.application_events where application_id=a and event_type='cancelled')<>1 then raise exception 'Cancellation history lost'; end if;
 execute 'reset role';
end $$;
select 'Cancellation, replay, no-inference, terminal notes, reopening, register, dashboard and KPI checks passed' result;
rollback;
