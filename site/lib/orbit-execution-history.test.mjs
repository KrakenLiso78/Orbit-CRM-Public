import test from 'node:test';
import assert from 'node:assert/strict';
import { readLatestProcessExecutions, mergeExecutionHistory } from './orbit-execution-history.mjs';
const run = (id, monitor_type, started_at) => ({ id, monitor_type, started_at, execution_key: id, completed_at: started_at, status: 'partial', scope: { quarter: '2026-Q4', latest_promotion: false }, scheduler: 'codex_local', dependency_note: null, summary: { signals_saved: 1 }, failures: [] });
void test('a busy job history retains the older latest market execution without duplicate or altered evidence', () => {
  const recent = Array.from({ length: 10 }, (_, i) => run(`job-${i}`, 'job_discovery', `2026-10-10T${String(20-i).padStart(2,'0')}:00:00Z`));
  const market = run('market', 'market_review', '2026-10-09T08:25:04Z');
  const merged = mergeExecutionHistory(recent, [recent[0], market]);
  assert.equal(merged.length, 11);
  assert.equal(merged[0], recent[0]);
  assert.equal(merged.at(-1), market);
  assert.deepEqual(market.scope, { quarter: '2026-Q4', latest_promotion: false });
  assert.equal(market.status, 'partial');
});
void test('latest reads are bounded, authenticated, process-specific and exclude owner columns', async () => {
  const headers = { apikey: 'synthetic-public-key', Authorization: 'Bearer synthetic-owner-token' };
  const rows = await readLatestProcessExecutions(async (url, options) => {
    const query = new URL(url).searchParams;
    assert.equal(query.get('limit'), '1');
    assert.equal(query.get('order'), 'started_at.desc,id.desc');
    assert.ok(!query.get('select').includes('owner_id'));
    assert.equal(options.headers, headers);
    const type = query.get('monitor_type').slice(3);
    return { ok: true, json: async () => [run(type, type, '2026-10-09T08:25:04Z')] };
  }, 'https://synthetic.example', headers);
  assert.equal(rows.length, 2);
});
void test('denied or malformed latest evidence fails instead of presenting a complete snapshot', async () => {
  await assert.rejects(readLatestProcessExecutions(async () => ({ ok: false }), 'https://synthetic.example', {}));
  await assert.rejects(readLatestProcessExecutions(async () => ({ ok: true, json: async () => [{}] }), 'https://synthetic.example', {}));
  assert.throws(() => mergeExecutionHistory([{}], []));
});
