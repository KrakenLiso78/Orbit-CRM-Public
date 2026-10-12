-- Synthetic candidate decisions and monitoring retries; no real job is changed.
begin;
set local statement_timeout = '15s';
create temporary table dismissal_results(name text, passed boolean);
grant select, insert on dismissal_results to authenticated;
do $$
declare
  o uuid := '81000000-0000-0000-0000-000000000011';
  other_owner uuid := '81000000-0000-0000-0000-000000000012';
  c uuid := '82000000-0000-0000-0000-000000000011';
  j uuid; a uuid; r jsonb; run jsonb;
begin
  insert into auth.users(id, aud, role) values(o,'authenticated','authenticated'),(other_owner,'authenticated','authenticated');
  insert into public.crm_owner_profiles(owner_id) values(o),(other_owner);
  insert into public.companies(id,owner_id,name) values(c,o,'Synthetic dismissal company');
  insert into public.candidate_profile_versions(owner_id,version_label,profile_data) values(o,'synthetic-dismiss-profile','{}');
  insert into public.scoring_rubric_versions(owner_id,version_label,rubric_data) values(o,'synthetic-dismiss-rubric','{}');
  run := jsonb_build_object('execution_key','synthetic-dismiss-before','profile_label','synthetic-dismiss-profile','rubric_label','synthetic-dismiss-rubric','status','succeeded','started_at','2026-10-11T10:00:00Z','completed_at','2026-10-11T10:01:00Z','roles',jsonb_build_array(jsonb_build_object('company_name','Synthetic dismissal company','title','Synthetic long role','source_name','Synthetic careers','source_identifier','dismiss-test','source_url','https://example.invalid/dismiss-test','score',94,'confidence',0.99,'first_seen_at','2026-10-11T10:00:00Z','last_seen_at','2026-10-11T10:00:00Z','captured_at','2026-10-11T10:00:00Z','assessed_at','2026-10-11T10:00:00Z','description_summary','Synthetic description','notify',true)));
  perform set_config('request.jwt.claim.sub',o::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  execute 'set local role authenticated';
  perform public.record_job_monitor_run(run,'synthetic-dismiss-before');
  select id into j from public.job_postings where owner_id=o;
  select id into a from public.fit_assessments where owner_id=o;
  insert into dismissal_results values ('Assessed role is initially visible',jsonb_array_length(public.get_orbit_mvp_snapshot()->'job_roles')=1);
  begin perform public.dismiss_job_posting(j,'   '); raise exception 'blank accepted'; exception when invalid_parameter_value then insert into dismissal_results values('Blank reason rejected',true); end;
  begin perform public.dismiss_job_posting(j,repeat('x',2001)); raise exception 'long reason accepted'; exception when invalid_parameter_value then insert into dismissal_results values('Long reason rejected',true); end;
  r := public.dismiss_job_posting(j,'Prefer a different scope');
  insert into dismissal_results values
    ('Exact retry returns the original decision',r=public.dismiss_job_posting(j,'Prefer a different scope')),
    ('Separate readback preserves reason, date and assessment',r=public.read_back_job_dismissal(j) and r->>'reason'='Prefer a different scope' and r->>'dismissed_at' is not null and (r->>'assessment_id')::uuid=a),
    ('Dismissed role removed from shortlist',jsonb_array_length(public.get_orbit_mvp_snapshot()->'job_roles')=0),
    ('Reason visible in dismissal history',public.get_orbit_mvp_snapshot() #>> '{dismissed_jobs,0,reason}'='Prefer a different scope');
  begin perform public.dismiss_job_posting(j,'Different'); raise exception 'reason overwritten'; exception when invalid_parameter_value then insert into dismissal_results values('Changed retry cannot overwrite decision',true); end;
  begin insert into public.job_dismissals(owner_id,job_posting_id,reason) values(o,j,'Bypass'); raise exception 'direct write accepted'; exception when insufficient_privilege then insert into dismissal_results values('Direct table write denied',true); end;
  run := jsonb_set(run,'{execution_key}','"synthetic-dismiss-after"');
  run := jsonb_set(run,'{roles,0,description_summary}','"Synthetic changed description"');
  perform public.record_job_monitor_run(run,'synthetic-dismiss-after');
  insert into dismissal_results values
    ('Rediscovery does not restore the shortlist',jsonb_array_length(public.get_orbit_mvp_snapshot()->'job_roles')=0),
    ('Rediscovery does not revive notification',not exists(select 1 from public.private_notifications where owner_id=o and notification_type='job_shortlist' and state='unread')),
    ('Source vacancy remains open',(select status='open' from public.job_postings where id=j)),
    ('Historical fit assessment retained',exists(select 1 from public.fit_assessments where id=a));
  execute 'reset role';
  perform set_config('request.jwt.claim.sub',other_owner::text,true);
  execute 'set local role authenticated';
  insert into dismissal_results values('Wrong owner cannot read decisions',not exists(select 1 from public.job_dismissals));
  begin perform public.read_back_job_dismissal(j); raise exception 'wrong owner read'; exception when no_data_found then insert into dismissal_results values('Wrong owner readback denied',true); end;
  begin perform public.dismiss_job_posting(j,'Foreign'); raise exception 'wrong owner write'; exception when no_data_found then insert into dismissal_results values('Wrong owner write denied',true); end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.dismiss_job_posting(j,'Expired'); raise exception 'expired write'; exception when insufficient_privilege then insert into dismissal_results values('Missing or expired identity denied',true); end;
  insert into dismissal_results values
    ('Anonymous RPC execution denied',not has_function_privilege('anon','public.dismiss_job_posting(uuid,text)','execute')),
    ('Anonymous table access denied',not has_table_privilege('anon','public.job_dismissals','select')),
    ('Exactly one persisted decision',(select count(*)=1 from public.job_dismissals where owner_id=o));
end; $$;
do $$ begin if exists(select 1 from dismissal_results where passed is distinct from true) then raise exception 'dismissal regression failed'; end if; end; $$;
select name,passed from dismissal_results order by name;
rollback;
