import test from 'node:test';
import assert from 'node:assert/strict';
import { parseJobRadar,readJobRadar } from './orbit-job-radar.mjs';
const companies=Array.from({length:25},(_,i)=>`Company ${i}`);
const rows=companies.map((name,i)=>({id:`source-${i}`,companies:{name},source_name:'Official careers',source_url:'https://official.example/jobs',status:i===24?'manual_review':'active',cadence_days:i<10?1:5,priority_rank:i+1,last_checked_at:null,last_successful_at:null,next_due_at:null,last_error:null}));
void test('the complete radar retains 25 companies independently of shortlist or missing freshness',()=>{
  assert.equal(parseJobRadar(rows,companies).length,25);
  assert.equal(parseJobRadar(rows,companies)[24].status,'manual_review');
  assert.equal(parseJobRadar(rows,companies)[24].last_checked_at,null);
});
void test('incomplete, duplicate, insecure and truncated radar evidence fails closed',()=>{
  assert.throws(()=>parseJobRadar(rows.slice(0,24),companies));
  assert.throws(()=>parseJobRadar([...rows,rows[0]],companies));
  assert.throws(()=>parseJobRadar(rows.map((r,i)=>i===0?{...r,source_url:'http://invalid.example'}:r),companies));
  assert.throws(()=>parseJobRadar(Array(100).fill(rows[0]),companies));
});
void test('radar reads use bounded display fields and provided owner auth; denied response is not an empty success',async()=>{
  const headers={apikey:'synthetic',Authorization:'Bearer synthetic'};
  const result=await readJobRadar(async(url,options)=>{const q=new URL(url).searchParams;assert.equal(q.get('limit'),'100');assert.ok(!q.get('select').includes('owner_id'));assert.equal(options.headers,headers);return {ok:true,json:async()=>rows};},'https://synthetic.example',headers,companies);
  assert.equal(result.length,25);
  await assert.rejects(()=>readJobRadar(async()=>({ok:false}),'https://synthetic.example',headers,companies));
});
