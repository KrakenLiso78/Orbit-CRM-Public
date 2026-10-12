-- Preserve company and opportunity together; other exclusive contexts remain exclusive.
alter table public.interactions drop constraint interactions_check;
alter table public.interactions add constraint interactions_check check (context_application_id is null or (context_company_id is null and context_opportunity_id is null));
alter table public.tasks drop constraint tasks_check;
alter table public.tasks add constraint tasks_check check (context_application_id is null or (context_company_id is null and context_opportunity_id is null));
alter table public.market_signals drop constraint market_signals_check;
alter table public.market_signals add constraint market_signals_check check (context_job_posting_id is null or (context_company_id is null and context_opportunity_id is null));
