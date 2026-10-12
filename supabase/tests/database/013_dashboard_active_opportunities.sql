-- Traceability: Personal CRM US7.2, US10, FR-049 and SC-016.
begin;
create temporary table active_lane_results(name text, passed boolean);
grant select,insert on active_lane_results to authenticated;
do $$
declare o uuid := '81000000-0000-0000-0000-000000000013'; c uuid := '82000000-0000-0000-0000-000000000013'; s jsonb;
begin
 insert into auth.users(id,aud,role) values(o,'authenticated','authenticated');
 insert into public.crm_owner_profiles(owner_id) values(o);
 insert into public.companies(id,owner_id,name) values(c,o,'Synthetic active lane');
 insert into public.opportunities(owner_id,company_id,title,status) select o,c,'Synthetic '||state,state from unnest(array['Rechazada','rejected','Cancelada','cancelled','canceled','Cerrada','closed','Retirada','withdrawn','Archivada','archived','unknown','Open',' Contacto hecho ','Screening']) state;
 perform set_config('request.jwt.claim.sub',o::text,true);
 execute 'set local role authenticated';
 s:=public.get_dashboard_snapshot();
 insert into active_lane_results values
 ('Only three active states survive terminal variants',jsonb_array_length(s->'active_opportunities')=3),
 ('All registered records remain in the KPI',(s #>> '{counts,opportunities}')::int=15),
 ('Filtering precedes the lane limit',exists(select 1 from jsonb_array_elements(s->'active_opportunities') x where x->>'status'='Open')),
 ('All stored opportunities are preserved',(select count(*)=15 from public.opportunities where owner_id=o)),
 ('Anonymous snapshot execution denied',not has_function_privilege('anon','public.get_dashboard_snapshot(integer,integer)','execute'));
 execute 'reset role';
end; $$;
do $$ begin if exists(select 1 from active_lane_results where passed is distinct from true) then raise exception 'active lane regression failed'; end if; end; $$;
select * from active_lane_results;
rollback;
