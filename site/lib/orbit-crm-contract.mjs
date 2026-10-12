function isRecord(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

export function parseDashboardSnapshot(value) {
  if (!isRecord(value) || !isRecord(value.counts)) throw new Error('Invalid CRM dashboard response.');
  const countKeys = ['companies', 'contacts', 'opportunities', 'applications', 'open_tasks'];
  if (countKeys.some((key) => !Number.isInteger(value.counts[key]) || value.counts[key] < 0)) throw new Error('Invalid CRM dashboard counts.');
  for (const key of ['due_tasks', 'recent_completed_tasks', 'recent_interactions', 'active_opportunities', 'recent_applications']) {
    if (!Array.isArray(value[key])) throw new Error(`Invalid CRM dashboard ${key}.`);
  }
  for (const task of value.recent_completed_tasks) {
    if (!isRecord(task)
      || typeof task.id !== 'string'
      || typeof task.title !== 'string'
      || typeof task.completed_at !== 'string'
      || !Array.isArray(task.events)) throw new Error('Invalid CRM dashboard completed task.');
    for (const key of ['source_interaction_id', 'source_interaction_title']) {
      if (task[key] !== null && typeof task[key] !== 'string') throw new Error(`Invalid CRM dashboard completed task ${key}.`);
    }
    for (const event of task.events) {
      if (!isRecord(event)
        || typeof event.id !== 'string'
        || typeof event.event_type !== 'string'
        || typeof event.occurred_at !== 'string'
        || (event.note !== null && typeof event.note !== 'string')) throw new Error('Invalid CRM dashboard task event.');
    }
  }
  for (const application of value.recent_applications) {
    if (!isRecord(application)
      || typeof application.id !== 'string'
      || typeof application.company_name !== 'string'
      || typeof application.submitted_at !== 'string'
      || typeof application.channel !== 'string') throw new Error('Invalid CRM dashboard application.');
    for (const key of ['role_title', 'current_state', 'state_recorded_at', 'latest_event_type', 'latest_event_at', 'latest_event_note']) {
      if (application[key] !== null && typeof application[key] !== 'string') throw new Error(`Invalid CRM dashboard application ${key}.`);
    }
  }
  return value;
}

export function parseMvpSnapshot(value) {
  if (!isRecord(value) || typeof value.generated_at !== 'string') throw new Error('Invalid Orbit MVP response.');
  for (const key of ['job_roles', 'market_signals', 'executions', 'notifications']) {
    if (!Array.isArray(value[key])) throw new Error(`Invalid Orbit MVP ${key}.`);
  }
  if (value.dismissed_jobs === undefined) value = { ...value, dismissed_jobs: [] };
  if (!Array.isArray(value.dismissed_jobs)) throw new Error('Invalid dismissed jobs.');
  for (const job of value.dismissed_jobs) {
    if (!isRecord(job) || typeof job.id !== 'string' || typeof job.reason !== 'string' || typeof job.dismissed_at !== 'string') throw new Error('Invalid dismissal.');
  }
  for (const role of value.job_roles) {
    if (!isRecord(role) || typeof role.title !== 'string' || typeof role.company_name !== 'string') throw new Error('Invalid Orbit MVP job role.');
    if (role.score !== null && (typeof role.score !== 'number' || role.score < 0 || role.score > 100)) throw new Error('Invalid Orbit MVP fit score.');
  }
  return value;
}

export function parseJobPostingPromotion(value, expectedJobId) {
  if (!isRecord(value)
    || value.saved !== true
    || value.application_created !== false
    || !isRecord(value.job_posting)
    || !isRecord(value.opportunity)
    || value.job_posting.id !== expectedJobId
    || typeof value.job_posting.opportunity_id !== 'string'
    || value.job_posting.opportunity_id !== value.opportunity.id
    || typeof value.job_posting.source_url !== 'string'
    || !value.job_posting.source_url.startsWith('https://')) {
    throw new Error('Invalid promotion readback.');
  }
  return value;
}
