import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseDashboardSnapshot, parseJobPostingPromotion, parseMvpSnapshot } from './orbit-crm-contract.mjs';

const loginPage = readFileSync(new URL('../app/crm/page.tsx', import.meta.url), 'utf8');
assert.ok(loginPage.includes('type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="username"'));
assert.ok(loginPage.includes('type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password"'));
assert.ok(loginPage.includes("'Avanzar y abrir candidatura'"));
assert.ok(loginPage.includes("'Pursue and open application'"));
assert.ok(loginPage.includes('promoteJobPostingToOpportunity(role.id)'));
assert.ok(loginPage.includes('getDashboardSnapshot()'));
assert.ok(loginPage.includes('applicationTab.location.replace(saved.job_posting.source_url)'));

const valid = {
  counts: { companies: 1, contacts: 2, opportunities: 0, applications: 0, open_tasks: 1 },
  due_tasks: [],
  recent_completed_tasks: [{
    id: 'task-1', title: 'Completed follow-up', completed_at: '2026-10-05T00:00:00Z',
    source_interaction_id: 'interaction-1', source_interaction_title: 'Source conversation',
    events: [
      { id: 'event-1', event_type: 'created', occurred_at: '2026-10-01T00:00:00Z', note: null },
      { id: 'event-2', event_type: 'completed', occurred_at: '2026-10-05T00:00:00Z', note: 'Done.' },
    ],
  }],
  recent_interactions: [],
  active_opportunities: [],
  recent_applications: [{
    id: 'application-1', company_name: 'Company', role_title: 'Role', submitted_at: '2026-10-01T00:00:00Z', channel: 'website',
    current_state: 'rejected', state_recorded_at: '2026-10-03T00:00:00Z', latest_event_type: 'follow_up',
    latest_event_at: '2026-10-04T00:00:00Z', latest_event_note: 'Asked for feedback.',
  }],
};

assert.deepEqual(parseDashboardSnapshot(valid), valid);
assert.throws(() => parseDashboardSnapshot({ ...valid, counts: { ...valid.counts, contacts: -1 } }));
assert.throws(() => parseDashboardSnapshot({ ...valid, recent_interactions: null }));
assert.throws(() => parseDashboardSnapshot({ ...valid, recent_completed_tasks: [{ ...valid.recent_completed_tasks[0], completed_at: null }] }));
assert.throws(() => parseDashboardSnapshot({ ...valid, recent_completed_tasks: [{ ...valid.recent_completed_tasks[0], events: [{ event_type: 'completed' }] }] }));
assert.throws(() => parseDashboardSnapshot({ ...valid, recent_applications: [{ ...valid.recent_applications[0], current_state: 2 }] }));
assert.throws(() => parseDashboardSnapshot({ counts: valid.counts }));
const mvp = { generated_at: '2026-10-07T00:00:00Z', job_roles: [{ title: 'Role', company_name: 'Company', score: 80 }], market_signals: [], executions: [], notifications: [] };
assert.deepEqual(parseMvpSnapshot(mvp), { ...mvp, dismissed_jobs: [] });
assert.throws(() => parseMvpSnapshot({ ...mvp, dismissed_jobs: [{ id: "job", reason: null, dismissed_at: "date" }] }));
assert.throws(() => parseMvpSnapshot({ ...mvp, job_roles: [{ title: 'Role', company_name: 'Company', score: 101 }] }));
assert.throws(() => parseMvpSnapshot({ ...mvp, executions: null }));
const promotion = {
  saved: true, application_created: false,
  job_posting: { id: 'job-1', opportunity_id: 'opportunity-1', source_url: 'https://careers.example/jobs/1' },
  opportunity: { id: 'opportunity-1' },
};
assert.deepEqual(parseJobPostingPromotion(promotion, 'job-1'), promotion);
assert.throws(() => parseJobPostingPromotion({ ...promotion, application_created: true }, 'job-1'));
assert.throws(() => parseJobPostingPromotion({ ...promotion, job_posting: { ...promotion.job_posting, opportunity_id: 'other' } }, 'job-1'));
assert.throws(() => parseJobPostingPromotion({ ...promotion, job_posting: { ...promotion.job_posting, source_url: 'http://insecure.example' } }, 'job-1'));
console.log('orbit-crm-contract: passed');
