// Local fixture only. No production API, device or external page is contacted.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFileSync,mkdirSync,writeFileSync,copyFileSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const fixture=JSON.parse(readFileSync(new URL('./fixtures/products-summary.json',import.meta.url),'utf8'));
const html=readFileSync(new URL('../site/index.html',import.meta.url),'utf8');
const script=readFileSync(new URL('../site/app.js',import.meta.url),'utf8');
const previewLabel='<p style="margin:12px 24px;color:#d7b074;font:14px system-ui">界面预览 · 模拟统计 / Preview · synthetic statistics</p>';
test('country dashboard filters both languages, preserves zero/unknown distinctions and fits mobile',async()=>{
 let current=fixture,status=200,live=false;
 const server=createServer((req,res)=>{
  if(req.url==='/data.json'){res.writeHead(status,{'content-type':'application/json'});res.end(JSON.stringify(current));return}
  if(req.url==='/app.js'){res.writeHead(200,{'content-type':'application/javascript'});res.end(script);return}
  if(req.url==='/'){res.writeHead(200,{'content-type':'text/html'});res.end(html.replace('<main>',previewLabel+'<main>'));return}
  res.writeHead(404);res.end();
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const base=`http://127.0.0.1:${server.address().port}`;
 const browser=await chromium.launch({headless:true});
 const page=await browser.newPage({viewport:{width:1100,height:1000}});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('**/*',route=>route.request().url().startsWith(base+'/')?route.continue():live?route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(fixture)}):route.abort());
 const screenshotDir=process.env.USAGE_SCREENSHOT_DIR?resolve(process.env.USAGE_SCREENSHOT_DIR):null;
 if(screenshotDir){
  mkdirSync(screenshotDir,{recursive:true});
  writeFileSync(join(screenshotDir,'index.html'),html.replace('<main>',previewLabel+'<main>'));
  writeFileSync(join(screenshotDir,'app.js'),script);
  copyFileSync(new URL('./fixtures/products-summary.json',import.meta.url),join(screenshotDir,'data.json'));
 }
 const shot=async name=>{if(screenshotDir)await page.screenshot({path:join(screenshotDir,name+'.png'),fullPage:true})};
 try{
  await page.goto(base);await page.waitForFunction(()=>document.querySelector('#total').textContent==='12');
  assert.equal(await page.locator('#active').textContent(),'8');assert.equal(await page.locator('#regions').textContent(),'3');
  await page.locator('#language').click();assert.equal(await page.locator('#product-label').textContent(),'分类');
  assert.equal(await page.locator('#product option[value=all]').textContent(),'全部');
  await shot('all-zh');
  await page.selectOption('#product','decent_remote');assert.equal(await page.locator('#total').textContent(),'7');assert.equal(await page.locator('#active').textContent(),'5');assert.equal(await page.locator('#rows tr').count(),2);
  await page.selectOption('#product','this_cup');assert.equal(await page.locator('#total').textContent(),'5');assert.equal(await page.locator('#active').textContent(),'3');assert.equal(await page.locator('#regions').textContent(),'2');assert.equal(await page.locator('#rows tr').count(),3);assert.match(await page.locator('#rows').textContent(),/未知/);
  await shot('this-cup-zh');
  await page.locator('#language').click();assert.equal(await page.inputValue('#product'),'this_cup');assert.equal(await page.locator('#product option[value=this_cup]').textContent(),'This Cup');assert.match(await page.locator('#rows').textContent(),/Unknown/);
  await page.setViewportSize({width:360,height:800});
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await shot('this-cup-en-mobile');
  current={...fixture,total_installations:0,active_30d:0,countries:[],products:fixture.products.map(p=>({product:p.product,total_installations:0,active_30d:0,countries:[]}))};
  await page.reload();await page.waitForFunction(()=>document.querySelector('#total').textContent==='0');await page.selectOption('#product','this_cup');assert.equal(await page.locator('#total').textContent(),'0');assert.match(await page.locator('#message').textContent(),/No installations/);assert(await page.locator('#table').isHidden());
  current={schema:1,generated_at:fixture.generated_at,scope:fixture.scope,...fixture.products[0]};delete current.product;
  await page.reload();await page.waitForFunction(()=>document.querySelector('#total').textContent==='7');await page.selectOption('#product','this_cup');assert.equal(await page.locator('#total').textContent(),'—');assert.match(await page.locator('#message').textContent(),/not available/);
  status=503;await page.reload();await page.waitForFunction(()=>document.querySelector('#message').textContent.includes('could not be loaded'));assert.equal(await page.locator('#total').textContent(),'—');
  live=true;await page.reload();await page.waitForFunction(()=>document.querySelector('#total').textContent==='12');await page.selectOption('#product','this_cup');assert.equal(await page.locator('#total').textContent(),'5');
  assert.deepEqual(errors,[]);
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
});
