// Only the legacy redirect lives here. Dashboard tests belong to usage-stats.
// Both origins below are served or intercepted locally; no live service is used.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const html=readFileSync(new URL('../site/index.html',import.meta.url),'utf8');
const destination='https://chowjw-vibecode.github.io/usage-stats/';
const legacyPath='/de1app-plugin-decent-remote/';

async function fixture(t,{automatic=true,width=1100}={}){
  // Disable only the refresh in this fixture to exercise its manual fallback.
  const refresh=/<meta\b[^>]*http-equiv=["']refresh["'][^>]*>/i;
  assert.match(html,refresh,'The legacy entry must declare its redirect');
  const source=automatic?html:html.replace(refresh,'');
  const localRequests=[],externalRequests=[];
  const server=createServer((req,res)=>{
    localRequests.push(req.url);
    if(req.url===legacyPath){res.writeHead(200,{'content-type':'text/html; charset=utf-8'});res.end(source);return;}
    res.writeHead(404);res.end();
  });
  let browser;
  t.after(async()=>{await browser?.close();await new Promise(resolve=>server.close(resolve));});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base='http://127.0.0.1:'+server.address().port;
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width,height:800},javaScriptEnabled:false});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('**/*',route=>{
    const url=route.request().url();
    if(url.startsWith(base+'/'))return route.continue();
    externalRequests.push(url);
    if(url===destination)return route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html lang="zh-CN"><title>Local destination fixture</title><h1>统一统计测试页</h1></html>'});
    return route.abort();
  });
  return {page,url:base+legacyPath,localRequests,externalRequests,errors};
}

test('legacy project URL redirects to the exact shared statistics URL without JavaScript',async t=>{
  const f=await fixture(t);
  await f.page.goto(f.url);
  await f.page.waitForURL(destination,{timeout:5000});
  assert.equal(await f.page.locator('h1').innerText(),'统一统计测试页');
  assert.deepEqual(f.externalRequests,[destination]);
  assert(!f.localRequests.some(url=>/\/(?:app\.js|data\.json)/.test(url)));
  assert.deepEqual(f.errors,[]);
});

for(const width of [1100,360])test('manual fallback remains usable without automatic refresh at '+width+'px',async t=>{
  const f=await fixture(t,{automatic:false,width});
  await f.page.goto(f.url);
  assert.equal(await f.page.locator('html').getAttribute('lang'),'zh-CN');
  assert.equal(await f.page.locator('link[rel=canonical]').getAttribute('href'),destination);
  const link=f.page.getByRole('link',{name:'打开统计页面',exact:true});
  assert.equal(await link.getAttribute('href'),destination);
  assert(await link.isVisible());
  assert.equal(await f.page.locator('script').count(),0);
  assert(await f.page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  assert.deepEqual(f.externalRequests,[]);
  await link.click();await f.page.waitForURL(destination,{timeout:5000});
  assert.deepEqual(f.externalRequests,[destination]);
  assert.deepEqual(f.errors,[]);
});
