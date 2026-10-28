import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import worker,{handle} from '../worker.mjs';
const NOW=2000000000, ID='a'.repeat(32), OTHER='b'.repeat(32);
function fixture(){
 const db=new DatabaseSync(':memory:');db.exec(readFileSync(new URL('../schema.sql',import.meta.url),'utf8'));
 const limits=[];
 const env={
  DB:{
   prepare(sql){
    return {bind(...args){
     return {
      async run(){return db.prepare(sql).run(...args)},
      async all(){return {results:db.prepare(sql).all(...args)}}
     };
    }};
   }
  },
  RATE_LIMITER:{async limit(value){limits.push(value);return {success:true}}}
 };
 return {db,env,limits};
}
function request({path='/v1/check-in',method='POST',body={install_id:ID},country='CN',type='application/json',raw,protocol='https:'}={}){
 const r=new Request(protocol+'//usage.test'+path,{method,headers:{'content-type':type,'cf-connecting-ip':'192.0.2.1'},...(method==='GET'?{}:{body:raw??JSON.stringify(body)})});
 Object.defineProperty(r,'cf',{value:{country}});return r;
}
async function summary(env,now=NOW){return (await handle(request({method:'GET',path:'/v1/summary'}),env,now)).json()}
test('repeat reports count one installation; only a hash and country/time are stored',async()=>{
 const {db,env,limits}=fixture();
 try{
  assert.equal((await handle(request(),env,NOW)).status,200);await handle(request(),env,NOW+604800);
  const rows=db.prepare('SELECT * FROM installations').all();assert.equal(rows.length,1);assert.match(rows[0].id_hash,/^[0-9a-f]{64}$/);assert.notEqual(rows[0].id_hash,ID);
  assert.deepEqual(Object.keys(rows[0]),['id_hash','country','first_seen','last_seen']);assert.equal(rows[0].first_seen,NOW);assert.equal(rows[0].last_seen,NOW+604800);
  const s=await summary(env,NOW+604800);assert.equal(s.total_installations,1);assert.equal(s.active_30d,1);assert.equal(s.countries[0].country,'CN');
  assert(!JSON.stringify(s).includes('id_hash'));assert(!JSON.stringify(s).includes(ID));assert(!JSON.stringify(limits).includes('192.0.2.1'));
 }finally{db.close()}
});
test('current country changes without double-counting and stale reports leave the 30-day total',async()=>{
 const {db,env}=fixture();try{
  await handle(request(),env,NOW);await handle(request({country:'GB'}),env,NOW+1);await handle(request({body:{install_id:OTHER},country:'US'}),env,NOW+31*86400);
  const s=await summary(env,NOW+31*86400);assert.equal(s.total_installations,2);assert.equal(s.active_30d,1);assert(!s.countries.some(r=>r.country==='CN'));assert.equal(s.countries.find(r=>r.country==='US').active_30d,1);
 }finally{db.close()}
});
test('missing or special location is Unknown; no client-supplied country is accepted',async()=>{
 const {db,env}=fixture();try{
  for(const country of [null,'XX','EU','T1','USA']){await handle(request({country}),env,NOW);assert.equal((await summary(env)).countries[0].country,'ZZ')}
  assert.equal((await handle(request({body:{install_id:ID,country:'US'}}),env,NOW)).status,422);
 }finally{db.close()}
});
test('malformed, extra, oversized, non-string or wrong-type input cannot write data',async()=>{
 const {db,env}=fixture();try{
  for(const body of [null,[],{}, {install_id:[ID]}, {install_id:12}, {install_id:'x'.repeat(32)}, {install_id:ID,profile:'private'}])assert.equal((await handle(request({body}),env,NOW)).status,422);
  assert.equal((await handle(request({raw:'{'}),env,NOW)).status,400);
  assert.equal((await handle(request({raw:' '.repeat(300)}),env,NOW)).status,413);
  assert.equal((await handle(request({type:'application/jsonp'}),env,NOW)).status,415);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM installations').get().n,0);
 }finally{db.close()}
});
test('deletion is idempotent and removes only the supplied installation',async()=>{
 const {db,env}=fixture();try{
  await handle(request(),env,NOW);await handle(request({body:{install_id:OTHER}}),env,NOW);
  for(let i=0;i<2;i++)assert.equal((await handle(request({method:'DELETE'}),env,NOW)).status,200);
  assert.equal((await summary(env)).total_installations,1);
 }finally{db.close()}
});
test('unknown routes, methods, no HTTPS or missing configuration do not write',async()=>{
 const {db,env}=fixture();try{
  assert.equal((await handle(request({path:'/private'}),env,NOW)).status,404);
  assert.equal((await handle(request({method:'PUT'}),env,NOW)).status,405);
  assert.equal((await handle(request({protocol:'http:'}),env,NOW)).status,426);
  assert.equal((await handle(request(),{DB:env.DB},NOW)).status,503);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM installations').get().n,0);
 }finally{db.close()}
});
test('rate limiting blocks writes and outages expose no database details',async()=>{
 const {db,env}=fixture();try{
  env.RATE_LIMITER.limit=async()=>({success:false});assert.equal((await handle(request(),env,NOW)).status,429);assert.equal((await summary({...env,RATE_LIMITER:{limit:async()=>({success:true})}})).total_installations,0);
  env.RATE_LIMITER.limit=async()=>{throw new Error('private database details')};const r=await worker.fetch(request(),env);assert.equal(r.status,503);assert.equal(await r.text(),'{"error":"temporarily_unavailable"}');
 }finally{db.close()}
});

test('out-of-order writes keep the latest country and earliest check-in; equal timestamps keep existing country',async()=>{
 const {db,env}=fixture();try{
  await handle(request({country:'US'}),env,NOW+100);
  await handle(request({country:'GB'}),env,NOW);
  const row=db.prepare('SELECT country,first_seen,last_seen FROM installations').get();
  assert.equal(row.country,'US');assert.equal(row.first_seen,NOW);assert.equal(row.last_seen,NOW+100);
  await handle(request({country:'CN'}),env,NOW+100);
  assert.equal(db.prepare('SELECT country FROM installations').get().country,'US');
 }finally{db.close()}
});
