import test from 'node:test';
import assert from 'node:assert/strict';
import { buildRankFlow } from './rank-flow.mjs';
import { syntheticMarket } from './synthetic-market.mjs';
void test('synthetic graphic retains 25 identities and explicit unavailable values', () => {
  const before = JSON.stringify(syntheticMarket);
  const model = buildRankFlow(syntheticMarket);
  assert.equal(model.rows.length, 25);
  assert.equal(new Set(model.rows.map(row => row.id)).size, 25);
  assert.equal(model.rankedCount, 15);
  assert.equal(model.projectedCount, 13);
  assert.equal(model.rows.filter(row => row.projected === null).length, 12);
  assert.equal(JSON.stringify(syntheticMarket), before);
});
void test('overlapping ranges have separate contained display rows', () => {
  const model = buildRankFlow(syntheticMarket);
  const ys = model.rows.map(row => row.rightY).sort((a,b) => a-b);
  assert.equal(new Set(ys).size, 25);
  assert.ok(ys.slice(1).every((y,index) => y-ys[index] >= 38));
  assert.ok(Math.max(...ys) < model.height);
});
void test('missing or invalid range never generates a forecast; duplicate identity fails', () => {
  const row = { id: 'synthetic', company: 'Synthetic', legacy_rank: null, projection: { status: 'not_reviewed', rank_range: [2,4] } };
  assert.equal(buildRankFlow({ companies: [row] }).rows[0].projected, null);
  assert.throws(() => buildRankFlow({ companies: [row,row] }), /identity/);
});
void test('recorded synthetic midpoint is retained only within its range', () => {
  const row = { id: 'synthetic', company: 'Synthetic', legacy_rank: 3, projection: { status: 'carried_q3_orbit_estimate', rank_range: [2,4] } };
  assert.equal(buildRankFlow({companies:[row]}, {synthetic:3}).rows[0].midpoint,3);
  assert.equal(buildRankFlow({companies:[row]}, {synthetic:8}).rows[0].midpoint,null);
});
