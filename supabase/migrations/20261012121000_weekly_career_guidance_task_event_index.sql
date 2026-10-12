-- Cover the composite foreign key used to read weekly-guidance task events.
create index weekly_career_actions_task_event_idx
  on public.weekly_career_actions (owner_id, task_event_id)
  where task_event_id is not null;
