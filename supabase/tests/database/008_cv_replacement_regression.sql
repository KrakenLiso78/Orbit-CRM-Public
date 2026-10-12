-- Rolled-back synthetic fixtures exercise the deployed business RPCs.
-- No real owner, material, notification, application, or schedule is changed.
begin;
set local statement_timeout = '15s';
create temporary table cv_regression_results (name text, passed boolean);
create function pg_temp.reject_configuration(p_profile jsonb, p_label text, p_rubric jsonb, p_rubric_label text, p_sources jsonb, p_key text)
returns boolean language plpgsql as $$
begin
  perform public.configure_job_monitor(p_profile, p_label, p_rubric, p_rubric_label, p_sources, p_key);
  raise exception 'configuration unexpectedly accepted' using errcode = 'P0001';
exception when others then
  if sqlstate = '23505' then return true; end if;
  if sqlstate = 'P0001' then return false; end if;
  raise;
end;
$$;
grant execute on function pg_temp.reject_configuration(jsonb,text,jsonb,text,jsonb,text) to authenticated;
do $$
declare
  v_owner uuid := '81000000-0000-0000-0000-000000000008';
  v_company uuid := gen_random_uuid();
  v_material uuid := gen_random_uuid();
  v_cv1 uuid := gen_random_uuid();
  v_cv2 uuid := gen_random_uuid();
  v_app uuid := gen_random_uuid();
  v_profile1 jsonb := '{"evidence":"Synthetic CV v1","sources":["synthetic-ai-v1.pdf","synthetic-pharma-v1.pdf"]}';
  v_profile2 jsonb := '{"evidence":"Synthetic CV v2","sources":["synthetic-ai-v2.pdf","synthetic-pharma-v1.pdf"]}';
  v_rubric jsonb := '{"dimensions":["evidence"],"threshold":70}';
  v_sources jsonb := '[{"company_name":"Synthetic CV replacement","source_name":"Synthetic careers","source_url":"https://example.invalid/careers","cadence_days":1,"priority_rank":1}]';
  v_first jsonb;
  v_second jsonb;
  v_run jsonb;
  v_role jsonb;
  v_old_assessment jsonb;
  v_job uuid;
  v_snapshot uuid;
  v_old_profile uuid;
  v_new_profile uuid;
  v_ok boolean;
  v_checks jsonb := '[]';
begin
  insert into auth.users(id,aud,role) values(v_owner,'authenticated','authenticated');
  insert into public.crm_owner_profiles(owner_id) values(v_owner);
  insert into public.companies(id,owner_id,name) values(v_company,v_owner,'Synthetic CV replacement');
  insert into public.materials(id,owner_id,name,material_type) values(v_material,v_owner,'Synthetic CV','CV');
  insert into public.material_versions(id,owner_id,material_id,version_label,notes,approved_at)
    values(v_cv1,v_owner,v_material,'synthetic-v1','Original CV evidence',now());
  perform set_config('request.jwt.claim.sub',v_owner::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  execute 'set local role authenticated';
  v_first := public.configure_job_monitor(v_profile1,'synthetic-profile-v1',v_rubric,'synthetic-rubric-v1',v_sources,'synthetic-cv-config-v1');
  v_old_profile := (v_first #>> '{profile,id}')::uuid;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('name','Exact configuration retry preserves receipt and profile','passed',v_first = public.configure_job_monitor(v_profile1,'synthetic-profile-v1',v_rubric,'synthetic-rubric-v1',v_sources,'synthetic-cv-config-v1')));
  v_role := jsonb_build_object('company_name','Synthetic CV replacement','title','Synthetic AI role','source_name','Synthetic careers','source_identifier','synthetic-cv-role','source_url','https://example.invalid/role','status','open','first_seen_at',now(),'last_seen_at',now(),'captured_at',now(),'description_summary','Synthetic role description v1','score',60,'confidence',0.8,'rationale','Synthetic v1 assessment','gaps',jsonb_build_array('Synthetic gap'),'assessed_at',now(),'notify',false);
  v_run := jsonb_build_object('execution_key','synthetic-cv-run-v1','profile_label','synthetic-profile-v1','rubric_label','synthetic-rubric-v1','status','succeeded','started_at',now(),'completed_at',now(),'scheduler','manual','roles',jsonb_build_array(v_role));
  perform public.record_job_monitor_run(v_run,'synthetic-cv-run-v1');
  execute 'reset role';
  select to_jsonb(f) into v_old_assessment from public.fit_assessments f where owner_id=v_owner;
  v_job := (v_old_assessment ->> 'job_posting_id')::uuid;
  v_snapshot := (v_old_assessment ->> 'job_description_snapshot_id')::uuid;
  insert into public.applications(id,owner_id,company_id,job_posting_id,submission_snapshot_id,submitted_at,channel,submission_evidence)
    values(v_app,v_owner,v_company,v_job,v_snapshot,now(),'synthetic','Synthetic submission');
  insert into public.application_material_versions(owner_id,application_id,material_version_id) values(v_owner,v_app,v_cv1);
  insert into public.material_versions(id,owner_id,material_id,version_label,notes,approved_at)
    values(v_cv2,v_owner,v_material,'synthetic-v2','Replacement CV evidence',now());
  execute 'set local role authenticated';
  v_second := public.configure_job_monitor(v_profile2,'synthetic-profile-v2',v_rubric,'synthetic-rubric-v1',v_sources,'synthetic-cv-config-v2');
  v_new_profile := (v_second #>> '{profile,id}')::uuid;
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('name','Replacement profile gets a distinct version identifier','passed',v_new_profile <> v_old_profile));
  v_run := v_run || jsonb_build_object('execution_key','synthetic-cv-run-v2','profile_label','synthetic-profile-v2','roles',jsonb_build_array(v_role || jsonb_build_object('description_summary','Synthetic role description v2','score',80,'rationale','Synthetic v2 assessment')));
  perform public.record_job_monitor_run(v_run,'synthetic-cv-run-v2');
  v_ok := pg_temp.reject_configuration(v_profile2,'synthetic-profile-v1',v_rubric,'synthetic-rubric-v1',v_sources,'synthetic-overwrite-profile');
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('name','Changed profile cannot reuse an existing version label','passed',v_ok));
  v_ok := pg_temp.reject_configuration(v_profile2,'synthetic-profile-v2','{"dimensions":["different"]}','synthetic-rubric-v1',v_sources,'synthetic-overwrite-rubric');
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('name','Changed rubric cannot reuse an existing version label','passed',v_ok));
  v_checks := v_checks || jsonb_build_array(jsonb_build_object('name','Old configuration readback retains original profile content','passed',public.read_back_job_monitor_configuration('synthetic-cv-config-v1') #> '{profile,profile_data}' = v_profile1));
  execute 'reset role';
  insert into cv_regression_results select x->>'name',(x->>'passed')::boolean from jsonb_array_elements(v_checks) x;
  insert into cv_regression_results values
    ('Historical assessment retains all fields and original profile/rubric', (select to_jsonb(f)=v_old_assessment from public.fit_assessments f where id=(v_old_assessment->>'id')::uuid)),
    ('New assessment uses the replacement profile and new score',(select count(*)=1 from public.fit_assessments where owner_id=v_owner and candidate_profile_version_id=v_new_profile and score=80)),
    ('Submitted application retains original CV version',(select count(*)=1 and bool_and(material_version_id=v_cv1) from public.application_material_versions where application_id=v_app)),
    ('Application retains its original job description snapshot',(select submission_snapshot_id=v_snapshot from public.applications where id=v_app)),
    ('Original and replacement CV coexist',(select count(*)=2 from public.material_versions where material_id=v_material)),
    ('Historical job description remains unchanged',(select content_text='Synthetic role description v1' from public.job_description_snapshots where id=v_snapshot)),
    ('No shortlist notification is inferred',(select count(*)=0 from public.private_notifications where owner_id=v_owner));
  begin
    update public.material_versions set notes='Forbidden rewrite' where id=v_cv1;
    raise exception 'referenced CV rewrite unexpectedly accepted' using errcode='P0001';
  exception when others then
    if sqlstate='P0001' and sqlerrm like 'material version % is part of application evidence' then
      insert into cv_regression_results values('Submitted CV content cannot be rewritten',true);
    else raise; end if;
  end;
end;
$$;
do $$ begin
  if exists(select 1 from cv_regression_results where passed is distinct from true) then
    raise exception 'CV replacement regression failed';
  end if;
end; $$;
select name,passed from cv_regression_results order by name;
rollback;
