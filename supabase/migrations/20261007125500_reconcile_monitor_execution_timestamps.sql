-- Reconcile bootstrap timestamps that were recorded ahead of the database clock,
-- then prevent inverted execution intervals. Historical request receipts remain intact.
update public.monitor_executions
set completed_at = created_at
where completed_at is not null and completed_at > created_at;

update public.monitor_executions
set started_at = completed_at
where completed_at is not null and started_at > completed_at;

alter table public.monitor_executions
  add constraint monitor_executions_time_order_check
  check (completed_at is null or started_at <= completed_at);
