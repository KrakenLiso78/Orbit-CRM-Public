import test from 'node:test';
import assert from 'node:assert/strict';
import { resultMetrics, recordedFailures, evidenceLabel, executionTime } from './orbit-executions.mjs';
void test('job/market metrics preserve zeroes without deriving counts from flags or text', () => {
  assert.deepEqual(resultMetrics({ roles_assessed: 23, notifications_created: 0, not_hiring_probability: true }), [['roles_assessed', 23], ['notifications_created', 0]]);
  assert.deepEqual(resultMetrics({ signals_saved: 1, source_failures: 1, controls: { build: 'passed' } }), [['signals_saved', 1], ['source_failures', 1]]);
  assert.deepEqual(resultMetrics(null), []);
});
void test('heterogeneous failures preserve source/reason and leave missing causes absent', () => {
  assert.deepEqual(recordedFailures([{ kind: 'incomplete_enumeration', source: 'Synthetic source', detail: 'Enumeration failed' }, { type: 'source_retrieval' }, 'Original error', null]), [
    { type: 'incomplete_enumeration', source: 'Synthetic source', reason: 'Enumeration failed' },
    { type: 'source_retrieval', source: null, reason: null }, { reason: 'Original error' }, { reason: null },
  ]);
  assert.deepEqual(recordedFailures(undefined), []);
});
void test('labels translate known keys and retain unknown evidence', () => {
  assert.equal(evidenceLabel('incomplete_enumeration', 'es'), 'Enumeración incompleta');
  assert.equal(evidenceLabel('signals_saved', 'en'), 'Saved signals');
  assert.equal(evidenceLabel('future_result', 'es'), 'future result');
});
void test('timestamps include Madrid time and handle absent/invalid completion', () => {
  assert.match(executionTime('2026-10-11T10:00:00Z', 'es'), /12:00/);
  assert.match(executionTime('2026-10-11T10:00:00Z', 'en'), /12:00/);
  assert.equal(executionTime(null, 'es'), 'No registrada');
  assert.equal(executionTime('invalid', 'en'), 'Not recorded');
});
