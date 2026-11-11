// Country-level installation counts. No device control or private configuration.
export const PRODUCTS = ['decent_remote','this_cup'];
export const UPSERT = `INSERT INTO installations (id_hash,product,country,first_seen,last_seen)
VALUES (?,?,?,?,?) ON CONFLICT(id_hash) DO UPDATE SET
country=CASE WHEN excluded.last_seen>last_seen THEN excluded.country ELSE country END,
first_seen=MIN(first_seen,excluded.first_seen),last_seen=MAX(last_seen,excluded.last_seen)`;
export const SUMMARY = `SELECT country,COUNT(*) AS installations,
SUM(CASE WHEN last_seen>=? THEN 1 ELSE 0 END) AS active_30d
FROM installations WHERE product='decent_remote'
GROUP BY country ORDER BY installations DESC,country`;
export const PRODUCT_SUMMARY = `SELECT product,country,COUNT(*) AS installations,
SUM(CASE WHEN last_seen>=? THEN 1 ELSE 0 END) AS active_30d
FROM installations GROUP BY product,country ORDER BY installations DESC,country`;
const WEEK = 7 * 86400;
const CORS = {'access-control-allow-origin':'*'};
const json = (data, status=200) => new Response(JSON.stringify(data), {
  status, headers: {...CORS,'content-type':'application/json; charset=utf-8','cache-control':'no-store'}
});
function totals(countries) {
  return {total_installations:countries.reduce((n,r)=>n+Number(r.installations),0),
    active_30d:countries.reduce((n,r)=>n+Number(r.active_30d),0),countries};
}
async function digest(value) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map(x=>x.toString(16).padStart(2,'0')).join('');
}
export async function handle(request, env, now=Math.floor(Date.now()/1000)) {
  const url = new URL(request.url);
  if (!env.DB || !env.RATE_LIMITER) return json({error:'not_configured'},503);
  if (url.protocol !== 'https:') return json({error:'https_required'},426);
  if (!['/v1/summary','/v2/summary','/v1/check-in'].includes(url.pathname)) return json({error:'not_found'},404);
  if (request.method === 'OPTIONS') {
    return new Response(null,{status:204,headers:{...CORS,
      'access-control-allow-methods':url.pathname==='/v1/check-in'?'POST, DELETE, OPTIONS':'GET, OPTIONS',
      'access-control-allow-headers':'Content-Type','access-control-max-age':'86400'}});
  }
  // Shared per-route limit; no IP addresses or installation identifiers enter the limiter.
  if (!(await env.RATE_LIMITER.limit({key:url.pathname})).success) return json({error:'rate_limited'},429);
  if (url.pathname.endsWith('/summary') && request.method === 'GET') {
    const meta={generated_at:new Date(now*1000).toISOString(),scope:'reporting installations; not people or all users'};
    if (url.pathname === '/v1/summary') {
      const {results} = await env.DB.prepare(SUMMARY).bind(now-30*86400).all();
      return json({schema:1,...meta,...totals(results)});
    }
    // One database snapshot supplies both product totals and the combined total.
    const {results} = await env.DB.prepare(PRODUCT_SUMMARY).bind(now-30*86400).all();
    const products=PRODUCTS.map(product=>({product,...totals(results.filter(r=>r.product===product)
      .map(({country,installations,active_30d})=>({country,installations,active_30d})))}));
    const combined=new Map();
    for (const {country,installations,active_30d} of results) {
      const row=combined.get(country)||{country,installations:0,active_30d:0};
      row.installations+=Number(installations);row.active_30d+=Number(active_30d);combined.set(country,row);
    }
    const countries=[...combined.values()].sort((a,b)=>b.installations-a.installations||a.country.localeCompare(b.country));
    return json({schema:2,...meta,...totals(countries),products});
  }
  if (url.pathname !== '/v1/check-in') return json({error:'not_found'},404);
  if (request.method !== 'POST' && request.method !== 'DELETE') return json({error:'method_not_allowed'},405);
  if ((request.headers.get('content-type')||'').split(';')[0].trim().toLowerCase() !== 'application/json') return json({error:'json_required'},415);
  // Stream with a byte cap; do not buffer an arbitrarily large body.
  const reader=request.body?.getReader();if(!reader)return json({error:'invalid_body'},400);
  let size=0,parts=[];
  for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>256){await reader.cancel();return json({error:'too_large'},413)}parts.push(value)}
  const bytes=new Uint8Array(size);let offset=0;for(const p of parts){bytes.set(p,offset);offset+=p.length}
  let body;try{body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes))}catch{return json({error:'invalid_json'},400)}
  if(!body||Array.isArray(body)||Object.keys(body).some(k=>!['install_id','product'].includes(k))||typeof body.install_id!=='string'||!/^[a-f0-9]{32}$/.test(body.install_id))return json({error:'invalid_installation'},422);
  const product=Object.hasOwn(body,'product')?body.product:'decent_remote';
  if(!PRODUCTS.includes(product))return json({error:'invalid_product'},422);
  // Preserve old hashes and scope new products independently, including deletion.
  const id=await digest(product==='decent_remote'?body.install_id:product+':'+body.install_id);
  if(request.method==='DELETE'){
    await env.DB.prepare('DELETE FROM installations WHERE id_hash=? AND product=?').bind(id,product).run();
    return json({deleted:true});
  }
  // Only the hosting platform supplies location. Ignore all client country/IP fields.
  const source=request.cf?.country;
  const country=typeof source==='string'&&/^[A-Z]{2}$/.test(source)&&!['EU','XX'].includes(source)?source:'ZZ';
  await env.DB.prepare(UPSERT).bind(id,product,country,now,now).run();
  return json({accepted:true,next_check_in_after_s:WEEK});
}
export default {async fetch(request,env){try{return await handle(request,env)}catch{return json({error:'temporarily_unavailable'},503)}}};
