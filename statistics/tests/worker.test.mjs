import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import worker,{handle} from '../worker.mjs';
const NOW=2000000000, ID='a'.repeat(32), OTHER='b'.repeat(32);
function fixture(schema=readFileSync(new URL('../schema.sql',import.meta.url),'utf8')){
 const db=new DatabaseSync(':memory:');db.exec(schema);
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
  assert.deepEqual(Object.keys(rows[0]),['id_hash','product','country','first_seen','last_seen','version']);assert.equal(rows[0].product,'decent_remote');assert.equal(rows[0].first_seen,NOW);assert.equal(rows[0].last_seen,NOW+604800);
  const s=await summary(env,NOW+604800);assert.equal(s.total_installations,1);assert.equal(s.active_30d,1);assert.equal(s.countries[0].country,'CN');
  assert(!JSON.stringify(s).includes('id_hash'));assert(!JSON.stringify(s).includes(ID));assert(!JSON.stringify(limits).includes('192.0.2.1'));
 }finally{db.close()}
});

async function productSummary(env,now=NOW){return (await handle(request({method:'GET',path:'/v2/summary'}),env,now)).json()}
test('migration preserves existing hashes, countries and dates; old clients update and delete the same record',async()=>{
 const oldSchema=`CREATE TABLE installations(id_hash TEXT PRIMARY KEY,country TEXT NOT NULL,first_seen INTEGER NOT NULL,last_seen INTEGER NOT NULL);CREATE INDEX installations_last_seen ON installations(last_seen)`;
 const {db,env}=fixture(oldSchema);
 try{
  const hash=createHash('sha256').update(ID).digest('hex');
  db.prepare('INSERT INTO installations VALUES (?,?,?,?)').run(hash,'SG',NOW-100,NOW-10);
  db.exec(readFileSync(new URL('../migrations/0001_products.sql',import.meta.url),'utf8'));
  assert.deepEqual({...db.prepare('SELECT * FROM installations').get()},{id_hash:hash,country:'SG',first_seen:NOW-100,last_seen:NOW-10,product:'decent_remote'});
  db.exec(readFileSync(new URL('../migrations/0002_versions.sql',import.meta.url),'utf8'));
  assert.equal(db.prepare('SELECT version FROM installations').get().version,null);
  assert.equal((await summary(env)).total_installations,1);
  await handle(request({country:'GB'}),env,NOW);
  const row=db.prepare('SELECT * FROM installations').get();
  assert.equal(row.id_hash,hash);assert.equal(row.country,'GB');assert.equal(row.first_seen,NOW-100);assert.equal(row.last_seen,NOW);
  await handle(request({method:'DELETE'}),env,NOW);
  assert.equal((await summary(env)).total_installations,0);
 }finally{db.close()}
});
test('categories count the same random ID separately; v1 remains Decent Remote only',async()=>{
 const {db,env}=fixture();try{
  await handle(request({country:'SG'}),env,NOW-31*86400);
  await handle(request({country:'CN',body:{install_id:ID,product:'this_cup'}}),env,NOW);
  await handle(request({country:'CN',body:{install_id:ID,product:'this_cup'}}),env,NOW+1);
  const legacy=await summary(env,NOW+1);
  assert.deepEqual(legacy,{schema:1,generated_at:new Date((NOW+1)*1000).toISOString(),scope:'reporting installations; not people or all users',total_installations:1,active_30d:0,countries:[{country:'SG',installations:1,active_30d:0}]});
  const s=await productSummary(env,NOW+1);
  assert.equal(s.schema,2);assert.equal(s.total_installations,2);assert.equal(s.active_30d,1);
  assert.deepEqual(s.countries,[{country:'CN',installations:1,active_30d:1},{country:'SG',installations:1,active_30d:0}]);
  assert.deepEqual(s.products,[{product:'decent_remote',total_installations:1,active_30d:0,countries:[{country:'SG',installations:1,active_30d:0}],versions:[{version:null,installations:1,active_30d:0}]},{product:'this_cup',total_installations:1,active_30d:1,countries:[{country:'CN',installations:1,active_30d:1}],versions:[{version:null,installations:1,active_30d:1}]}]);
  const rows=db.prepare('SELECT id_hash FROM installations').all();assert.equal(new Set(rows.map(r=>r.id_hash)).size,2);
  assert(!JSON.stringify(s).includes(ID));assert(!JSON.stringify(s).includes('id_hash'));
  await handle(request({method:'DELETE',body:{install_id:ID,product:'this_cup'}}),env,NOW+2);
  assert.equal((await summary(env)).total_installations,1);
  assert.equal((await productSummary(env)).products[1].total_installations,0);
  await handle(request({method:'DELETE'}),env,NOW+3);
  assert.equal((await productSummary(env)).total_installations,0);
 }finally{db.close()}
});
test('explicit old category and omitted category deduplicate; country aggregates reconcile across products',async()=>{
 const {db,env}=fixture();try{
  await handle(request(),env,NOW);
  await handle(request({body:{install_id:ID,product:'decent_remote'}}),env,NOW+1);
  await handle(request({body:{install_id:OTHER,product:'this_cup'}}),env,NOW+1);
  const s=await productSummary(env,NOW+1);
  assert.equal(s.total_installations,2);assert.deepEqual(s.countries,[{country:'CN',installations:2,active_30d:2}]);
  assert.deepEqual(s.products.map(p=>p.total_installations),[1,1]);
 }finally{db.close()}
});
test('missing categories remain present with zero totals; unsupported products and private fields are rejected',async()=>{
 const {db,env}=fixture();try{
  const s=await productSummary(env);assert.equal(s.total_installations,0);
  assert.deepEqual(s.products.map(p=>[p.product,p.total_installations,p.countries]),[['decent_remote',0,[]],['this_cup',0,[]]]);
  for(const product of ['',null,1,{},[],true,'This Cup','decent-remote','other'])assert.equal((await handle(request({body:{install_id:ID,product}}),env,NOW)).status,422);
  for(const field of ['country','ip','device_id','profile'])assert.equal((await handle(request({body:{install_id:ID,product:'this_cup',[field]:'private'}}),env,NOW)).status,422);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM installations').get().n,0);
 }finally{db.close()}
});
test('browser preflight and success/error responses permit anonymous cross-origin access without credentials',async()=>{
 const {db,env,limits}=fixture();try{
  const preflight=new Request('https://usage.test/v1/check-in',{method:'OPTIONS',headers:{origin:'http://tablet.test:8080','access-control-request-method':'POST','access-control-request-headers':'content-type'}});
  const response=await handle(preflight,env,NOW);
  assert.equal(response.status,204);assert.equal(await response.text(),'');
  assert.equal(response.headers.get('access-control-allow-origin'),'*');
  assert.match(response.headers.get('access-control-allow-methods'),/POST/);assert.match(response.headers.get('access-control-allow-methods'),/DELETE/);
  assert.equal(response.headers.get('access-control-allow-headers'),'Content-Type');
  assert.equal(response.headers.get('access-control-allow-credentials'),null);assert.equal(limits.length,0);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM installations').get().n,0);
  for(const r of [request(),request({body:{install_id:ID,product:'bad'}}),request({method:'GET',path:'/v2/summary'}),request({path:'/private'})]){
   const result=await handle(r,env,NOW);assert.equal(result.headers.get('access-control-allow-origin'),'*');assert.equal(result.headers.get('access-control-allow-credentials'),null);
  }
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


test('version migration keeps all historical rows unchanged apart from explicit unknown version',()=>{
 const schema=readFileSync(new URL('../schema.sql',import.meta.url),'utf8').replace(/,\n    version TEXT[^\n]+/,'');
 const {db}=fixture(schema);try{
  db.prepare('INSERT INTO installations VALUES (?,?,?,?,?)').run('a'.repeat(64),'this_cup','CN',NOW-10,NOW);
  const before={...db.prepare('SELECT * FROM installations').get()};
  db.exec(readFileSync(new URL('../migrations/0002_versions.sql',import.meta.url),'utf8'));
  assert.deepEqual({...db.prepare('SELECT * FROM installations').get()},{...before,version:null});
 }finally{db.close()}
});
test('newer version reports move the existing installation; absent and out-of-order versions cannot erase or roll it back',async()=>{
 const {db,env}=fixture();try{
  const report=(version,time)=>handle(request({body:{install_id:ID,product:'this_cup',...(version===undefined?{}:{version})}}),env,time);
  await report(undefined,NOW);await report('0.2.31',NOW+1);await report('0.2.32',NOW+3);
  await report('0.2.30',NOW+2);await report(undefined,NOW+4);
  const row=db.prepare('SELECT * FROM installations').get();
  assert.equal(row.version,'0.2.32');assert.equal(row.first_seen,NOW);assert.equal(row.last_seen,NOW+4);
  assert.equal(db.prepare('SELECT COUNT(*) n FROM installations').get().n,1);
  const s=await productSummary(env,NOW+4);assert.deepEqual(s.products[1].versions,[{version:'0.2.32',installations:1,active_30d:1}]);
  assert.equal((await summary(env)).total_installations,0);
 }finally{db.close()}
});
test('version totals reconcile with country and product totals, including unknown and inactive installations',async()=>{
 const {db,env}=fixture();try{
  const inputs=[['a','this_cup','0.2.31','CN',NOW],['b','this_cup','0.2.31','GB',NOW],['c','this_cup','0.2.32','CN',NOW],['d','this_cup',undefined,'CN',NOW-31*86400],['e','decent_remote','0.3.5','CN',NOW]];
  for(const [id,product,version,country,time] of inputs)await handle(request({country,body:{install_id:id.repeat(32),product,...(version?{version}:{})}}),env,time);
  const s=await productSummary(env);assert.equal(s.total_installations,5);assert.equal(s.active_30d,4);
  for(const p of s.products){
    assert.equal(p.versions.reduce((n,r)=>n+r.installations,0),p.total_installations);
    assert.equal(p.versions.reduce((n,r)=>n+r.active_30d,0),p.active_30d);
    assert.equal(p.countries.reduce((n,r)=>n+r.installations,0),p.total_installations);
    assert.equal(new Set(p.countries.map(r=>r.country)).size,p.countries.length);
  }
  assert.deepEqual(s.products[1].versions,[{version:'0.2.31',installations:2,active_30d:2},{version:'0.2.32',installations:1,active_30d:1},{version:null,installations:1,active_30d:0}]);
  assert(!Object.hasOwn(await summary(env),'versions'));
 }finally{db.close()}
});
test('only bounded valid SemVer strings are accepted; bad version/private fields never write',async()=>{
 const {db,env}=fixture();try{
  for(const version of [null,1,true,[],{},'', 'v0.2.31','0.2','01.2.3','1.02.3','1.2.03','1.2.3-01','1.2.3-a..b','1.2.3+', '1.2.3+bad space','1.2.3-'+ 'a'.repeat(60)]){
    const r=await handle(request({body:{install_id:ID,version}}),env,NOW);assert.equal(r.status,422,JSON.stringify(version));
  }
  assert.equal(db.prepare('SELECT COUNT(*) n FROM installations').get().n,0);
  for(const version of ['0.2.31','0.2.29-rc.11','1.2.3-alpha.1+build.005','0.0.0','1.2.3-0','1.2.3-'+ 'a'.repeat(58)])assert.equal((await handle(request({body:{install_id:ID,version}}),env,NOW)).status,200,version);
  assert.equal((await handle(request({body:{install_id:ID,version:'1.2.3',device_id:'private'}}),env,NOW)).status,422);
 }finally{db.close()}
});


test('same-second valid reports use arrival order and legitimate downgrades remain reportable',async()=>{
 const {db,env}=fixture();try{
  const report=(version,time)=>handle(request({body:{install_id:ID,product:'this_cup',...(version===undefined?{}:{version})}}),env,time);
  await report('0.2.30',NOW);await report('0.2.31',NOW);
  assert.equal(db.prepare('SELECT version FROM installations').get().version,'0.2.31');
  await report(undefined,NOW);assert.equal(db.prepare('SELECT version FROM installations').get().version,'0.2.31');
  await report('0.2.29',NOW+1);assert.equal(db.prepare('SELECT version FROM installations').get().version,'0.2.29');
  await report('0.2.32',NOW);assert.equal(db.prepare('SELECT version FROM installations').get().version,'0.2.29');
  assert.equal(db.prepare('SELECT COUNT(*) n FROM installations').get().n,1);
  assert.deepEqual((await productSummary(env,NOW+1)).products[1].versions,[{version:'0.2.29',installations:1,active_30d:1}]);
 }finally{db.close()}
});
