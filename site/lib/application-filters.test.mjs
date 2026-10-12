import test from 'node:test';
import assert from 'node:assert/strict';
import { filterApplications, parseApplicationRegister } from './application-filters.mjs';
const rows = ['submitted','rejected','withdrawn','cancelled',null].map((state,index)=>({id:index,company_name:index%2?'Synthetic A':'Synthetic B',current_state:state,role_title:'Synthetic product role',channel:index%2?'direct':'referral',submitted_at:`2026-01-0${index+1}T12:00:00Z`}));
void test('malformed register responses fail closed instead of crashing rendering',()=>{
 const row={...rows[0],id:'00000000-0000-4000-8000-000000000001'};
 assert.deepEqual(parseApplicationRegister([row]),[row]);
 assert.deepEqual(parseApplicationRegister([]),[]);
 for(const body of [null,{},[row,row],[{...row,submitted_at:'invalid'}],[{...row,channel:null}],[{...row,current_state:{}}],[{...row,role_title:42}]])assert.throws(()=>parseApplicationRegister(body),/unavailable/);
});
void test('all states remain available; combined filters and inclusive dates do not mutate history',()=>{
  const before=JSON.stringify(rows);
  assert.equal(filterApplications(rows,{}).length,5);
  assert.deepEqual(filterApplications(rows,{company:'Synthetic A',state:'cancelled',channel:'direct',query:'PRODUCT',from:'2026-01-04',to:'2026-01-04'}).map(r=>r.id),[3]);
  assert.equal(filterApplications(rows,{query:'absent'}).length,0);
  assert.deepEqual(filterApplications(rows,{state:'unknown'}).map(r=>r.id),[4]);
  assert.equal(filterApplications(rows,{from:'2026-01-04',to:'2026-01-02'}).length,0);
  assert.equal(filterApplications(rows,{}).length,5);
  assert.equal(JSON.stringify(rows),before);
});
