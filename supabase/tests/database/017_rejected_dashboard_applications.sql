-- FR-058: lifecycle rejection, pre-limit exclusion, notes and reopening.
begin;
do $$
declare own uuid:=gen_random_uuid(); company uuid:=gen_random_uuid(); a uuid; reopened uuid; result jsonb;
begin
 insert into auth.users(id,aud,role) values(own,'authenticated','authenticated');
 insert into public.crm_owner_profiles(owner_id) values(own);
 insert into public.companies(id,owner_id,name) values(company,own,'Synthetic rejection filter');
 for n in 1..10 loop
  insert into public.applications(owner_id,company_id,submitted_at,channel,submission_evidence)
   values(own,company,now()-n*interval '1 day','direct','Synthetic fixture') returning id into a;
  insert into public.application_events(owner_id,application_id,event_type,occurred_at,note,operation_key)
   values(own,a,case when n%2=0 then 'withdrawn' else 'rejected' end,now()-interval '1 hour','Synthetic terminal state','synthetic-rejection-'||n);
  insert into public.application_events(owner_id,application_id,event_type,occurred_at,note,operation_key)
   values(own,a,'follow_up',now(),'Synthetic later note','synthetic-note-'||n);
  reopened:=a;
 end loop;
 insert into public.applications(owner_id,company_id,submitted_at,channel,submission_evidence)
  values(own,company,now()-interval '20 days','direct','Synthetic older eligible application');
 perform set_config('request.jwt.claim.sub',own::text,true);
 execute 'set local role authenticated';
 result:=public.get_dashboard_snapshot();
 if jsonb_array_length(result->'recent_applications')<>1 then raise exception 'Rejected applications displaced eligible older application'; end if;
 if (result#>>'{counts,applications}')::int<>11 then raise exception 'Total KPI changed'; end if;
 if jsonb_array_length(public.get_application_register())<>11 then raise exception 'All-state register incomplete'; end if;
 if has_function_privilege('anon','public.get_application_register()','execute') then raise exception 'Anonymous register execution granted'; end if;
 execute 'reset role';
 insert into public.application_events(owner_id,application_id,event_type,occurred_at,note,operation_key)
  values(own,reopened,'reopened',now()+interval '1 minute','Synthetic reopening','synthetic-reopened');
 execute 'set local role authenticated';
 result:=public.get_dashboard_snapshot();
 if jsonb_array_length(result->'recent_applications')<>2 then raise exception 'Reopened application excluded'; end if;
 if (select count(*) from public.applications where owner_id=own)<>11 then raise exception 'History altered'; end if;
 execute 'reset role';
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 execute 'set local role authenticated';
 if jsonb_array_length(public.get_application_register())<>0 then raise exception 'Foreign owner register disclosed'; end if;
 execute 'reset role';
end $$;
select 'Rejected filtering, pre-limit eligibility, later-note exclusion, reopening and total preservation passed' as result;
rollback;
