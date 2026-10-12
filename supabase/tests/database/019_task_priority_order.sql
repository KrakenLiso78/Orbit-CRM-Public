begin;
do $$
declare own uuid:=gen_random_uuid(); result jsonb;
begin
 insert into auth.users(id,aud,role) values(own,'authenticated','authenticated');
 insert into public.crm_owner_profiles(owner_id) values(own);
 insert into public.tasks(owner_id,title,priority,state,due_at)
 select own,'Synthetic '||coalesce(p,'missing'),p,'0-Backlog',now()-n*interval '1 day'
 from unnest(array['P2','P1','P0',null]) with ordinality x(p,n);
 perform set_config('request.jwt.claim.sub',own::text,true);
 execute 'set local role authenticated';
 result:=public.get_dashboard_snapshot(2,8);
 if result#>>'{due_tasks,0,priority}'<>'P0' or result#>>'{due_tasks,1,priority}'<>'P1' then raise exception 'Priority or pre-limit selection failed'; end if;
 result:=public.get_dashboard_snapshot(8,8);
 if result#>>'{due_tasks,2,priority}'<>'P2' or jsonb_array_length(result->'due_tasks')<>4 then raise exception 'Priority/missing order failed'; end if;
 if (select count(*) from public.tasks where owner_id=own and priority is null)<>1 then raise exception 'Stored priorities changed'; end if;
 execute 'reset role';
end $$;
select 'P0/P1/P2/missing and pre-limit selection passed' result;
rollback;
