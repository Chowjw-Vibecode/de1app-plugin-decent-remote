#!/usr/bin/env node
// Production HTML with all API traffic intercepted. No device traffic or CDN.
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
const template=fs.readFileSync(path.join(__dirname,'fixtures/filter3.tcl'),'utf8');
const copy=x=>JSON.parse(JSON.stringify(x));
const step={name:'高压段',pump:'pressure',sensor:'coffee',transition:'fast',temperature:92,seconds:12,pressure:8.6,flow:0,volume:500,weight:24,max_flow_or_pressure:8,max_flow_or_pressure_range:.4,exit_if:1,exit_type:'flow_under',exit_flow_under:0,exit_flow_over:0,exit_pressure_under:0,exit_pressure_over:0,popup:'保留说明'};
const original={profile:'Demo_Two_Stage',title:'演示两段曲线',profile_type:'settings_2c',dose_g:20,yield_g:80,temperature_c:92,readback:'app_cache',editable_steps:true,steps:[step,{...step,name:'流量段',pump:'flow',flow:1.5,temperature:88,seconds:50,weight:0}],target_volume_ml:0,volume_count_start:0,notes:'original notes',dirty:false};
const shot={version:'2',elapsed:[0,.25,.5,1,12,20,43],pressure:{pressure:[0,1,2,4,8.6,2,2.2],goal:[-1,8.6,8.6,8.6,-1,-1,-1]},flow:{flow:[0,4,4,4,3,1.5,1.6],by_weight:[0,0,.1,.2,2.8,1.8,1.9],goal:[-1,-1,-1,-1,1.5,1.5,1.5]},temperature:{basket:[92,83,85,87,92,88.1,88.2],goal:[92,92,92,92,88,88,88]},totals:{weight:[0,0,0,1,24,50,80]},state_change:[0,10000000,10000000,10000000,-10000000,-10000000,-10000000],profile:{title:'合成历史样本',reference_file:'Demo_Two_Stage',steps:[{temperature:92}]},meta:{in:20,out:80.9,time:43}};
if(process.env.REMOTE_SCREENSHOT_DIR){
 original.title='Demo — two-stage espresso';original.steps[0].name='Pressure start';original.steps[1].name='Flow finish';
 // Synthetic samples solely for documentation; never claim these are shot data.
 const times=Array.from({length:173},(_,i)=>i*.25);
 const lerp=(t,points)=>{for(let i=1;i<points.length;i++){const [b,y]=points[i],[a,x]=points[i-1];if(t<=b)return x+(y-x)*(t-a)/(b-a)}return points.at(-1)[1]};
 shot.elapsed=times;
 shot.pressure.pressure=times.map(t=>Math.max(0,lerp(t,[[0,0],[1,.8],[4,1.3],[6,3],[7.5,8.9],[9,8.6],[12,8.6],[14,3.2],[17,2.3],[43,2.2]])+.025*Math.sin(t*2.3)));
 shot.pressure.goal=times.map(t=>t<12?8.6:-1);
 shot.flow.flow=times.map(t=>Math.max(0,lerp(t,[[0,0],[1,5.5],[3,6],[5,5.5],[8,2.4],[12,2.8],[15,1.6],[43,1.5]])+.035*Math.sin(t*3)));
 shot.flow.by_weight=times.map(t=>Math.max(0,lerp(t,[[0,0],[5,0],[7,2],[12,2.8],[16,1.8],[43,1.8]])+.03*Math.sin(t*2.4)));
 shot.flow.goal=times.map(t=>t<12?-1:1.5);
 shot.temperature.basket=times.map(t=>lerp(t,[[0,90],[1,84],[3,87],[7,91.5],[12,92],[16,88.7],[22,88.2],[43,88]])+.035*Math.sin(t));
 shot.temperature.goal=times.map(t=>t<12?92:88);
 let weight=0;shot.totals.weight=times.map((t,i)=>weight+=i?shot.flow.by_weight[i]*.25:0);
 shot.totals.weight=shot.totals.weight.map(w=>w*80/weight);
 shot.state_change=times.map(t=>t<12?10000000:-10000000);
 shot.profile.title='Demo — two-stage espresso';
 if(process.env.REMOTE_SCREENSHOT_SHOT){
  const recorded=JSON.parse(fs.readFileSync(process.env.REMOTE_SCREENSHOT_SHOT,'utf8'));
  const n=recorded.elapsed.length;
  const series=(values)=>{assert(Array.isArray(values)&&values.length===n&&values.every(v=>v!==''&&v!=null&&Number.isFinite(Number(v))),'Invalid recorded series');return values.map(Number)};
  shot.elapsed=series(recorded.elapsed);
  for(const [group,keys] of Object.entries({pressure:['pressure','goal'],flow:['flow','by_weight','goal'],temperature:['basket','goal']}))
   for(const key of keys)shot[group][key]=series(recorded[group][key]);
  shot.state_change=series(recorded.state_change);
  shot.totals={weight:[]}; // No synthetic weight trace; fixture summary is illustrative.
  shot.meta={in:original.dose_g,out:original.yield_g,time:shot.elapsed.at(-1)};
  assert(Object.values(shot.meta).every(Number.isFinite),'Invalid recorded metadata');
 }
}
const failures=[];let passed=0;
async function check(name,fn){try{await fn();passed++;console.log('PASS',name)}catch(e){failures.push({name,error:e.message});console.log('FAIL',name,e.message)}}
(async()=>{
 const browser=await chromium.launch({headless:true});
 async function fixture({empty=false,invalidAuth=false,failSettings=false,missingGoal=false,unconfirmed=false,dropWrite=false,failHistory=false,holdReceipt=false,remembered='',storageFailure=false,externalAfterAck=false,externalClean=false,sessionFailure=false,multipleShots=false,initialProfile=original}={}){
  const c=await browser.newContext({viewport:{width:1024,height:600},acceptDownloads:true,storageState:{cookies:[],origins:remembered?[{origin:'http://dashboard.test',localStorage:[{name:'decent-remote-access-key',value:remembered}]}]:[]}});if(storageFailure)await c.addInitScript(()=>{const old=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){if(k==='decent-remote-access-key')throw new DOMException('Blocked','SecurityError');return old.call(this,k,v)}});const page=await c.newPage(),calls=[],errors=[];let expectedKey='test-local-token',current=copy(initialProfile),saved=copy(initialProfile),active='Idle',offline=false,startEnabled=false,receiptReads=0,holding=holdReceipt,externalPending=false;
  if(sessionFailure)await c.addInitScript(()=>{Object.defineProperty(window,'sessionStorage',{get(){throw new DOMException('Blocked','SecurityError')}})});
  const detailFailures=new Set(),shotFiles={'20000102T103000.json':copy(shot)};
  if(multipleShots){
   shotFiles['20000102T102000.json']={...copy(shot),profile:{title:'原生基本曲线',steps:[{temperature:88}]},meta:{in:18,out:36,time:27}};
   shotFiles['20000102T101000.json']={...copy(shot),profile:{title:'Second synthetic shot',steps:[{temperature:91}]},meta:{in:19,out:60,time:32}};
   shotFiles['20000102T100000.shot']='profile_title {合成旧格式记录}\ngrinder_dose_weight 15\ndrink_weight 75\nespresso_elapsed {0 1 2}\nespresso_flow {0 4 4}\nespresso_weight {0 30 75}\n';
  }
  const files={'Demo_Two_Stage.tcl':template,'中文曲线.tcl':template.replace(/Filter3/g,'中文曲线')};let favorites={slots:[{slot:1,profile:'Demo_Two_Stage',title:original.title},{slot:2,profile:'中文曲线',title:'中文曲线'},...Array.from({length:3},(_,i)=>({slot:i+3,profile:'',title:''}))]};
  const config={settings:{preheat_phase1_flow_ml_s:2,preheat_phase2_flow_ml_s:4,preheat_timeout_s:30,idle_temperature_c:99,sleep_timeout_minutes:30,awake_brightness:80,sleep_brightness:40},controls:{flush_flow_ml_s:6,flush_timeout_s:5,hotwater_flow_ml_s:1,hotwater_temperature_c:70,hotwater_target:50,hotwater_target_unit:'g',hotwater_timeout_s:60,water_stop_on_scale:false,steam_enabled:true,steam_flow_ml_s:1.4,steam_temperature_c:160,steam_timeout_s:120,hotwater_target_warning:'杯重目标未生效'},scale:{require_scale:false,keep_scale_on:true,stop_before_s:.5},scheduler:{enabled:true,wake_time:'09:00',awake_until:'09:00'},charging:{smart_charging_mode:'off',machine_usb_enabled:true},'flow-compensation':{enabled:true,changes:[{target:1,command:.75,estimate:1.03}],last_profile:'Filter3',last_state:'confirmed'},shortcuts:{dose_yield:Array.from({length:4},(_,i)=>({slot:i+1,dose_g:15+i,yield_g:30+i*2})),temperatures:Array.from({length:4},(_,i)=>({slot:i+1,temperature_c:75+i*5}))}};
  page.on('pageerror',e=>errors.push(e.message));
  await c.route('**/*',async r=>{const req=r.request(),u=new URL(req.url());assert.equal(u.origin,'http://dashboard.test','No outside requests');if(u.pathname==='/')return r.fulfill({contentType:'text/html; charset=utf-8',body:html});
   const p=decodeURIComponent(u.pathname),method=req.method(),data=req.postData()?JSON.parse(req.postData()):null;
   calls.push({path:p,method,data,id:req.headers()['x-request-id'],auth:req.headers().authorization,url:req.url()});
   if(offline)return r.abort('connectionfailed');
   if(invalidAuth||req.headers().authorization!=='Bearer '+expectedKey)return r.fulfill({status:401,contentType:'application/json',body:JSON.stringify({error:'unauthorized',message:'访问密钥无效'})});
   const json=(x,status=200)=>r.fulfill({status,contentType:'application/json',body:JSON.stringify(x)});
   if(method!=='GET')assert.match(req.headers()['x-request-id']||'',/^web-[a-z0-9-]+$/);
   if(p.startsWith('/api/v1/requests/')){receiptReads++;if(holding)return json({accepted:true,app_applied:true,device_confirmed:false,phase:'frames_queued',in_flight:true});if(externalAfterAck&&!unconfirmed)externalPending=true;return json({accepted:true,app_applied:true,device_confirmed:!unconfirmed,phase:unconfirmed?'unconfirmed_timeout':'device_confirmed',in_flight:false})}
   if(p==='/api/v1/status')return json({state:active,connected:true,recipe:current,temperature_c:92.44,pressure_bar:.003,flow_ml_s:0,scale_weight_g:8.6,scale_connected:true,remote_start_enabled:startEnabled});
   if(p==='/api/v1/profile'){if(method==='POST'){const delta=data.temperature_c==null?0:data.temperature_c-current.temperature_c;Object.assign(current,data);if(delta&&!data.steps)current.steps.forEach(s=>s.temperature+=delta);if(data.yield_g!=null)current.target_volume_ml=0;current.dirty=true;current.temperature_c=current.steps[0].temperature;if(dropWrite)return r.abort('connectionreset');return json({accepted:true,readback:'app_cache',current_profile:current})}if(externalPending){current.steps[0].seconds=99;current.dirty=!externalClean;externalPending=false}return json(current)}
   if(p==='/api/v1/recipe'){Object.assign(current,data);current.dirty=true;if(dropWrite)return r.abort('connectionreset');return json({accepted:true,readback:'app_cache',recipe:current})}
   if(p==='/api/v1/profile/save'){saved=copy(current);current.dirty=false;return json({accepted:true,readback:'files'})}
   if(p==='/api/v1/profile/restore'){current=copy(saved);return json({accepted:true,current_profile:current,readback:'app_cache'})}
   if(p==='/api/v1/profile/save-as'){if(files[data.filename])return json({error:'exists',message:'文件名已存在'},409);current.profile=data.filename.replace(/\.tcl$/,'');current.title=data.title;current.dirty=false;files[data.filename]=template;saved=copy(current);return json({accepted:true,readback:'files'})}
   if(p==='/api/v1/profiles')return json(empty?[]:Object.keys(files));
   if(p==='/api/v1/profiles/import'){if(files[data.filename])return json({error:'exists',message:'文件名已存在'},409);if(!data.dry_run)files[data.filename]=data.content;return json({filename:data.filename,title:'导入',saved:!data.dry_run,readback:'file'})}
   if(p.startsWith('/api/v1/profiles/')){const name=p.split('/').at(-1);if(method==='PUT'){current={...copy(original),profile:name.replace(/\.tcl$/,''),title:'中文曲线'};return json({accepted:true,recipe:current})}if(!files[name])return json({error:'not_found'},404);return r.fulfill({contentType:'text/plain; charset=utf-8',body:files[name]})}
   if(p==='/api/v1/favorites'){if(method==='POST')favorites={slots:data.slots};return json(favorites)}
   if(failHistory&&p.startsWith('/api/v1/shots'))return json({error:'history_unavailable',message:'历史暂不可用'},503);
   if(p==='/api/v1/shots/json')return json(empty?[]:Object.keys(shotFiles).filter(n=>n.endsWith('.json')));
   if(p==='/api/v1/shots')return json(empty?[]:multipleShots?Object.keys(shotFiles).filter(n=>n.endsWith('.shot')):['20000102T103000.shot']);
   if(p.startsWith('/api/v1/shots/')){const filename=p.split('/').at(-1);if(shotFiles[filename]){
    if(multipleShots)await new Promise(resolve=>setTimeout(resolve,40));
    if(detailFailures.has(filename))return json({error:'synthetic_failure',message:'模拟读取失败'},503);
    if(filename.endsWith('.shot'))return r.fulfill({contentType:'text/plain; charset=utf-8',body:shotFiles[filename]});
    const x=copy(shotFiles[filename]);if(missingGoal){delete x.pressure.goal;delete x.flow.goal;delete x.temperature.goal}return json(x);
   }}
   if(p==='/api/v1/shots/20000102T103000.shot')return r.fulfill({contentType:'text/plain',body:'profile_title 合成记录\nespresso_elapsed {0 1 2}\n'});
   if(p==='/api/status/details')return json({espresso_elapsed:[0,1,2],espresso_pressure:[0,4,8],espresso_flow:[3,4,5],espresso_flow_weight:[0,0,1],espresso_temperature_basket:[82,90,92],espresso_weight:[0,1,2]});
   if(p==='/api/v1/scale/tare')return json({accepted:true});
   if(p.startsWith('/api/v1/machine/')){const op=p.split('/').at(-1);if(['espresso','flush','steam','hotwater'].includes(op)&&!startEnabled)return json({error:'start_disabled'},403);active=op==='sleep'?'Sleep':op==='wake'?'Idle':active;return json({accepted:true,readback:'app_cache'})}
   const key=p.split('/').at(-1);if(config[key]){if(failSettings)return json({error:'unsupported',message:'当前版本不可用'},501);if(method==='POST')Object.assign(config[key],data);return json({...config[key],readback:'app_cache'})}
   return json({error:'not_found',message:'Not mocked '+p},404);
  });
  await page.goto('http://dashboard.test/');return {c,page,calls,errors,files,config,detailFailures,get current(){return current},get receiptReads(){return receiptReads},offline:()=>{offline=true},online:()=>{offline=false},changeKey:v=>{expectedKey=v},setActive:v=>{active=v},startEnabled:()=>{startEnabled=true},confirm:value=>{unconfirmed=!value},release:()=>{holding=false},setFavorites:slots=>{favorites={slots}}};
 }
 async function login(f){await f.page.locator('#access-key').fill('test-local-token');await f.page.locator('#dialog-actions .primary').click();await f.page.waitForFunction(()=>state.authenticated&&lastShot!==undefined&&!!state.current);await f.page.waitForFunction(()=>!document.querySelector('#dialog').open);await f.page.waitForTimeout(150)}
 if(!process.env.REMOTE_SCREENSHOT_DIR){
 await check('home favorites show names in tablet order without loading or renaming on language changes',async()=>{
  const x=await fixture();try{await login(x);const buttons=x.page.locator('#home-favorites button');
   assert.equal(await buttons.count(),5);assert.equal(await buttons.nth(0).locator('.name').innerText(),original.title);assert.equal(await buttons.nth(1).locator('.name').innerText(),'中文曲线');
   assert.equal(await buttons.nth(0).getAttribute('aria-pressed'),'true');assert(await buttons.nth(4).isDisabled());
   await x.page.locator('#language-button').click();assert.equal(await buttons.nth(1).innerText(),'2\n中文曲线');assert.equal(await buttons.nth(4).locator('.name').innerText(),'Empty slot');
   assert(!x.calls.some(c=>c.method!=='GET'));assert.deepEqual(x.errors,[]);
  }finally{await x.c.close()}
 });
 await check('home favorite loads the recipe on the home page exactly once and never starts the machine',async()=>{
  const x=await fixture({initialProfile:{...copy(original),dose_g:19,yield_g:38,temperature_c:90}});try{await login(x);
   await x.page.locator('[data-home-fav="Demo_Two_Stage"]').click();assert(!x.calls.some(c=>c.method!=='GET'));
   await x.page.locator('[data-home-fav="中文曲线"]').click();await x.page.waitForFunction(()=>!state.busy&&state.current==='中文曲线');
   assert.equal(await x.page.evaluate(()=>state.page),'current');assert.equal(await x.page.locator('#home-profile').innerText(),x.current.title);
   for(const [field,key] of [['dose','dose_g'],['yield','yield_g'],['temp','temperature_c']])assert.equal(Number(await x.page.locator('#recipe-'+field).inputValue()),x.current[key]);
   assert.equal(await x.page.locator('[data-home-fav="中文曲线"]').getAttribute('aria-pressed'),'true');
   assert.deepEqual(x.calls.filter(c=>c.method!=='GET').map(c=>[c.path,c.method]),[['/api/v1/profiles/中文曲线.tcl','PUT']]);
  }finally{await x.c.close()}
 });
 await check('home favorite respects unsaved recipe changes on cancel and confirm',async()=>{
  const x=await fixture();try{await login(x);await x.page.locator('#recipe-dose').fill('18');await x.page.locator('[data-home-fav="中文曲线"]').click();
   await x.page.locator('#dialog-actions button').first().click();assert(!x.calls.some(c=>c.method!=='GET'));assert.equal(await x.page.locator('#recipe-dose').inputValue(),'18');
   await x.page.locator('[data-home-fav="中文曲线"]').click();await x.page.locator('#dialog-actions button').last().click();await x.page.waitForFunction(()=>!state.busy&&state.current==='中文曲线');
   assert.equal(await x.page.evaluate(()=>state.recipeDraft),null);assert.equal(x.calls.filter(c=>c.method==='PUT').length,1);
  }finally{await x.c.close()}
 });
 await check('home favorite waits for the outstanding load and does not send duplicates',async()=>{
  const x=await fixture({holdReceipt:true});try{await login(x);
   await x.page.locator('[data-home-fav="中文曲线"]').evaluate(b=>{b.click();b.click()});await x.page.waitForFunction(()=>state.busy);await x.page.waitForTimeout(100);
   assert.equal(x.calls.filter(c=>c.method==='PUT').length,1);assert(await x.page.locator('[data-home-fav="Demo_Two_Stage"]').isDisabled());
   assert.equal(await x.page.locator('[data-home-fav="Demo_Two_Stage"]').getAttribute('aria-pressed'),'true');
   x.release();await x.page.waitForFunction(()=>!state.busy&&state.current==='中文曲线');assert.equal(x.calls.filter(c=>c.method==='PUT').length,1);
  }finally{await x.c.close()}
 });
 await check('home favorites cannot load while brewing or disconnected and update after a tablet profile change',async()=>{
  const x=await fixture();try{await login(x);x.setActive('Espresso');await x.page.evaluate(()=>poll());assert(await x.page.locator('[data-home-fav="中文曲线"]').isDisabled());
   await x.page.evaluate(()=>loadHomeFavorite('中文曲线'));assert(!x.calls.some(c=>c.method!=='GET'));
   x.setActive('Idle');x.current.profile='outside-library';x.current.title='平板切换';await x.page.evaluate(()=>poll());assert.equal(await x.page.locator('#home-favorites [aria-pressed=true]').count(),0);
   x.offline();await x.page.evaluate(()=>poll());assert(await x.page.locator('[data-home-fav="中文曲线"]').isDisabled());assert(!x.calls.some(c=>c.method!=='GET'));
  }finally{await x.c.close()}
 });
 await check('home favorites management updates shortcuts immediately without selecting a recipe',async()=>{
  const x=await fixture();try{await login(x);await x.page.locator('#home-favorite-edit').click();await x.page.locator('[data-favorite-slot="1"]').selectOption('');await x.page.locator('[data-favorite-slot="4"]').selectOption('中文曲线');
   await x.page.locator('#dialog-actions .primary').click();await x.page.waitForFunction(()=>!state.busy&&favorites[4]==='中文曲线');
   assert.equal(await x.page.locator('#home-favorites button').nth(4).locator('.name').innerText(),'中文曲线');assert(await x.page.locator('#home-favorites button').nth(1).isDisabled());
   assert.equal(x.current.profile,original.profile);assert.equal(x.calls.filter(c=>c.method==='PUT').length,0);
  }finally{await x.c.close()}
 });
 await check('a favorite removed while confirming unsaved edits cannot be loaded',async()=>{
  const x=await fixture();try{await login(x);await x.page.locator('#recipe-dose').fill('18');await x.page.locator('[data-home-fav="中文曲线"]').click();
   x.setFavorites([{slot:1,profile:'Demo_Two_Stage',title:original.title}]);await x.page.evaluate(()=>refreshFavorites());
   await x.page.locator('#dialog-actions button').last().click();await x.page.waitForTimeout(50);
   assert(!x.calls.some(c=>c.method!=='GET'));assert.match(await x.page.locator('#receipt').innerText(),/常用曲线已改变/);await x.page.locator('#language-button').click();assert.equal(await x.page.locator('#receipt').innerText(),'Favorites have changed. Select a profile again.');
  }finally{await x.c.close()}
 });
 await check('home shortcut management stays on screen and compact recipe actions stay inside the card',async()=>{
  const x=await fixture();try{await login(x);for(const size of [{width:1024,height:600},{width:1280,height:800},{width:390,height:844},{width:320,height:844}]){
   await x.page.setViewportSize(size);for(const lang of ['zh','en']){if(await x.page.evaluate(()=>language)!==lang)await x.page.locator('#language-button').click();
    const manage=await x.page.locator('#home-favorite-edit').boundingBox();assert(manage.x>=0&&manage.x+manage.width<=size.width,'favorite management outside viewport');
    assert(await x.page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'page overflows horizontally');
    const langButton=await x.page.locator('#language-button').boundingBox();assert(langButton.x+langButton.width<=size.width,'language button clipped');
    for(const name of ['dose','yield','temp']){const field=await x.page.locator('#recipe-'+name).boundingBox();assert(field.width>=36,JSON.stringify({problem:'recipe value hidden',name,width:field.width,size,lang}))}
    for(const dirty of [false,true]){if(dirty)await x.page.locator('#recipe-dose').fill('18');
     const card=await x.page.locator('.recipe').boundingBox(),sleep=await x.page.locator('#sleep-button').boundingBox();assert(sleep.y+sleep.height<=card.y+card.height,JSON.stringify({problem:'recipe action outside card',size,lang,dirty,card,sleep}));
     if(dirty)await x.page.locator('#discard-recipe').click();
    }
   }
  }}finally{await x.c.close()}
 });
 await check('wake schedule explains the time window and matching times in both languages',async()=>{
  const x=await fixture();try{await login(x);await x.page.locator('nav [data-page=settings]').click();await x.page.locator('[data-group=schedule]').click();await x.page.waitForFunction(()=>settingsCache.has('schedule'));
   assert.match(await x.page.locator('#settings-body .setting-note').innerText(),/两个时间相同：只按时唤醒/);await x.page.locator('#language-button').click();
   assert.match(await x.page.locator('#settings-body .setting-note').innerText(),/Set both times the same/);assert(!/[\u4e00-\u9fff]/.test(await x.page.locator('#settings-body .setting-note').innerText()));
   await x.page.setViewportSize({width:390,height:844});for(const lang of ['zh','en']){
    if(await x.page.evaluate(()=>language)!==lang)await x.page.locator('#language-button').click();
    const panel=await x.page.locator('.settings-panel').boundingBox();for(const name of ['wakeTime','awakeUntil']){const field=await x.page.locator('[data-setting='+name+']').boundingBox();assert(field.x>=panel.x&&field.x+field.width<=panel.x+panel.width&&field.x+field.width<=390,'wake time field clipped')}
   }
   assert(!x.calls.some(c=>c.method!=='GET'));
  }finally{await x.c.close()}
 });
 if(process.env.REMOTE_HOME_TESTS_ONLY){await browser.close();console.log(JSON.stringify({passed,failed:failures.length,failures},null,2));process.exitCode=failures.length?1:0;return}
 await check('near-zero profile number boundary normalizes residuals and rejects real negatives',async()=>{
  const x=await fixture();try{const result=await x.page.evaluate(()=>{
   const outcome=value=>{try{return {value:profileNumber(value)}}catch{return {rejected:true}}};
   return {negativeBoundary:outcome(-1e-9),positiveBoundary:outcome(1e-9),negativeBeyond:outcome(-1e-8),positiveBeyond:outcome(1e-8)};
  });assert.deepEqual(result,{negativeBoundary:{value:0},positiveBoundary:{value:0},negativeBeyond:{rejected:true},positiveBeyond:{value:1e-8}});assert(!x.calls.some(c=>c.method!=='GET'));
  }finally{await x.c.close()}
 });
 await check('native basic stage labels localize without changing custom names',async()=>{
  const native={...copy(original),profile_type:'settings_2a',editable_steps:false,steps:[],display_steps_readback:'native_conversion',basic_parameters:{preinfusion_time:5},display_steps:['preinfusion temp boost','preinfusion boost','Custom stage'].map(name=>({...step,name}))};
  const x=await fixture({initialProfile:native});try{await login(x);await x.page.locator('nav [data-page=profiles]').click();
   assert.deepEqual(await x.page.locator('#stage-form .preview-stage strong').allTextContents(),['预浸温度补偿','预浸补偿','Custom stage']);
   await x.page.locator('#language-button').click();assert.deepEqual(await x.page.locator('#stage-form .preview-stage strong').allTextContents(),['preinfusion temp boost','preinfusion boost','Custom stage']);
   await x.page.locator('#language-button').click();assert.deepEqual(await x.page.locator('#stage-form .preview-stage strong').allTextContents(),['预浸温度补偿','预浸补偿','Custom stage']);
   assert(!x.calls.some(c=>c.method!=='GET'));assert.deepEqual(x.errors,[]);
  }finally{await x.c.close()}
 });
 await check('current basic profile shows only active type and enabled temperatures',async()=>{
  for(const [type,enabled] of [['settings_2a',0],['settings_2a',1],['settings_2b',0],['settings_2b',1]]){
   const basic_parameters={preinfusion_time:5,espresso_pressure:8,pressure_end:6,maximum_flow:4,flow_profile_hold:2,flow_profile_decline:1,maximum_pressure:9,espresso_temperature_steps_enabled:enabled,espresso_temperature_0:91,espresso_temperature_1:92,espresso_temperature_2:93,espresso_temperature_3:94,temp_bump_time_seconds:2,maximum_flow_range_default:1};
   const native={...copy(original),profile_type:type,editable_steps:false,steps:[],display_steps:[step],display_steps_readback:'native_conversion',basic_parameters};
   const x=await fixture({initialProfile:native});try{await login(x);await x.page.locator('nav [data-page=profiles]').click();const labels=await x.page.locator('#stage-form .setting-row label').allTextContents(),values=await x.page.locator('#stage-form .setting-row .num').allTextContents();
    assert(labels.includes('预浸最长时间'));assert.equal(labels.includes('维持压力'),type==='settings_2a');assert.equal(labels.includes('维持流量'),type==='settings_2b');
    for(const label of ['预浸温度','升压温度','维持温度','尾段温度'])assert.equal(labels.includes(label),!!enabled,`${type} ${enabled} ${label}`);
    if(enabled)for(const value of ['91 °C','92 °C','93 °C','94 °C'])assert(values.includes(value),`${type} ${value}`);
    assert(!x.calls.some(c=>c.method!=='GET'));assert.deepEqual(x.errors,[]);
   }finally{await x.c.close()}
  }
 });
 const names=await fixture();await login(names);
 await check('language switching preserves custom stage names and filenames',async()=>{
  await names.page.locator('nav [data-page=profiles]').click();
  const before=JSON.stringify(names.current);
  await names.page.locator('#language-button').click();
  await names.page.waitForTimeout(80);
  assert((await names.page.locator('[data-stage="0"]').innerText()).includes('高压段'));
  assert.equal(await names.page.locator('[data-profile="中文曲线"] [data-verbatim]').innerText(),'中文曲线');
  assert.equal(await names.page.locator('[data-fav="中文曲线"]').getAttribute('title'),'中文曲线');
  await names.page.locator('#language-button').click();await names.page.waitForTimeout(80);
  assert((await names.page.locator('[data-stage="0"]').innerText()).includes('高压段'));
  assert.equal(JSON.stringify(names.current),before);
  assert(!names.calls.some(c=>c.method!=='GET'));
 });
 await check('zoom and delete dialogs preserve user names and reset localization scope',async()=>{
  await names.page.locator('#language-button').click();
  await names.page.locator('nav [data-page=history]').click();await names.page.waitForSelector('#history-chart path.native-trace');
  await names.page.locator('[data-expand=history-chart]').click();await names.page.waitForTimeout(60);
  assert.equal(await names.page.locator('#dialog-title').innerText(),shot.profile.title);
  await names.page.locator('#dialog-actions button').click();
  await names.page.locator('nav [data-page=profiles]').click();await names.page.locator('#delete-stage').click();await names.page.waitForTimeout(60);
  assert.equal(await names.page.locator('#dialog-description').innerText(),'高压段');
  assert.equal(await names.page.locator('#dialog-title').innerText(),'Delete this stage?');
  await names.page.locator('#dialog-actions button').first().click();await names.page.locator('#about-button').click();await names.page.waitForTimeout(60);
  const version=JSON.parse(fs.readFileSync(path.join(__dirname,'../doc.json'),'utf8')).version;
  assert((await names.page.locator('#dialog-description').innerText()).includes(version+' · Control and status through de1app'));
  assert.equal(await names.page.locator('[data-field=exit] option[value=off]').innerText(),'Off');
  await names.page.locator('#dialog-actions button').click();
  await names.page.locator('#connect-button').click();await names.page.waitForTimeout(50);
  assert.equal(await names.page.locator('#dialog-actions button').first().innerText(),'Close');
  await names.page.locator('#dialog-actions button').first().click();
  assert(!names.calls.some(c=>c.method!=='GET'));
 });
 await check('English counts and empty favorite slot use natural labels',async()=>{
  assert.equal(await names.page.locator('#view-history .page-title>.tiny').innerText(),'1 shot');
  assert.equal(await names.page.evaluate(()=>displayTranslation('2 条记录')),'2 shots');
  assert.equal(await names.page.evaluate(()=>displayTranslation('1 段')),'1 stage');
  await names.page.locator('#favorite-edit-button').click();await names.page.waitForTimeout(60);
  assert.equal(await names.page.locator('[data-favorite-slot="0"] option[value=""]').innerText(),'Empty slot');
  await names.page.locator('#dialog-actions button').first().click();
 });
 await check('save-as defaults to an English suffix without translating the user title',async()=>{
  await names.page.locator('#save-as-profile').click();
  assert.equal(await names.page.locator('#new-title').inputValue(),original.title+' · Copy');
  await names.page.locator('#dialog-actions button').first().click();
  assert(!names.calls.some(c=>c.method!=='GET'));
 });
 await check('English confirmation and validation messages stay fully localized',async()=>{
  for(const source of ['当前参数未获得对应确认','曲线发送尚未确认；请先重新发送，确认后再保存','等待设备确认','设备尚未确认','正在发送…','已读取','重新发送','曲线发送尚未确认；请核对后再保存','平板上的曲线已改变，请重新读取后编辑','读取失败','连接失败','确认仍在等待；不会重复发送','请求未完成，请核对状态','请求被拒绝','当前版本不可用','记录读取失败','秤已连接且称重停止关闭：原生固件容量上限固定为250mL，所设目标容量不生效','仅调整参数，请用机器实体按键启动。']){
   await names.page.evaluate(s=>failUI(new Error(s)),source);await names.page.waitForTimeout(30);
   assert(!/[\u3400-\u9fff]/.test(await names.page.locator('#receipt').innerText()),source);
  }
  await names.page.locator('#language-button').click();await names.page.waitForTimeout(30);
  assert((await names.page.locator('#receipt').innerText()).includes('仅调整参数，请用机器实体按键启动。'));
 });await names.c.close();
 const emptyNames=await fixture({empty:true});await login(emptyNames);
 await check('empty history translates system text while custom shot titles stay intact',async()=>{
  await emptyNames.page.locator('#language-button').click();await emptyNames.page.locator('nav [data-page=history]').click();await emptyNames.page.waitForTimeout(60);
  assert.equal(await emptyNames.page.locator('#history-chart-title').innerText(),'No shots yet');
  assert.equal(await emptyNames.page.locator('#view-history .page-title>.tiny').innerText(),'0 shots');
  assert(!emptyNames.calls.some(c=>c.method!=='GET'));
 });await emptyNames.c.close();
 }
 const f=await fixture();
 await check('login exposes no synthetic values and makes no pre-auth request',async()=>{assert.equal(f.calls.length,0);assert.equal(await f.page.locator('#recipe-dose').inputValue(),'');assert((await f.page.locator('#readouts').innerText()).includes('—'))});
 await login(f);
 if(process.env.REMOTE_SCREENSHOT_DIR){
  // Documentation images use this isolated fixture, never a live device.
  const out=path.resolve(process.env.REMOTE_SCREENSHOT_DIR);fs.mkdirSync(out,{recursive:true});
  await f.page.setViewportSize({width:1440,height:900});
  await f.page.waitForFunction(n=>chartViews.get('home-chart')?.rows.length===n,shot.elapsed.length);
  const capture=async(name)=>{await f.page.waitForTimeout(180);await f.page.screenshot({path:path.join(out,name),fullPage:true})};
  await capture('current-zh-dark.png');
  await f.page.locator('#language-button').click();
  await capture('current-en-dark.png');
  await f.page.locator('nav [data-page=profiles]').click();
  await capture('profiles-en-dark.png');
  await f.page.locator('nav [data-page=history]').click();
  await capture('history-en-dark.png');
  await f.page.locator('#theme-button').click();
  await f.page.locator('nav [data-page=settings]').click();
  await capture('settings-en-light.png');
  await f.page.locator('#language-button').click();
  await f.page.locator('nav [data-page=current]').click();
  await capture('current-zh-light.png');
  await browser.close();console.log('Documentation screenshots saved from mocked data; no device traffic.');return;
 }
 await check('live recipe and exact telemetry readback',async()=>{assert.equal(await f.page.locator('#recipe-dose').inputValue(),'20');assert.equal(await f.page.locator('#home-profile').innerText(),'演示两段曲线');assert((await f.page.locator('#readouts').innerText()).includes('92.4'))});
 await check('authenticated same-origin requests keep key out of URL/storage',async()=>{assert(f.calls.every(x=>!x.url.includes('token')&&x.auth==='Bearer test-local-token'));assert.equal(await f.page.evaluate(()=>Object.values(localStorage).join('')).then(s=>s.includes('test-local-token')),false)});
 await check('history uses measured arrays and native phase divider',async()=>{await f.page.waitForFunction(()=>chartViews.get('home-chart')?.rows.length===7);assert.equal(await f.page.locator('#home-chart .stage-divider').count(),1);assert.equal(await f.page.locator('#home-chart [data-trace]').count(),4)});
 await check('hover header reads nearest measured sample',async()=>{await f.page.locator('#home-chart').focus();await f.page.keyboard.press('End');assert.equal(await f.page.locator('.chart-panel:has(#home-chart) .chart-time').innerText(),'43.00 s');assert.equal(await f.page.locator('.chart-panel:has(#home-chart) [data-readout=temp]').getAttribute('data-value'),'88.2');await f.page.keyboard.press('Escape')});
 await check('removed start controls stay absent even with a legacy enabled response',async()=>{
  f.startEnabled();await f.page.evaluate(()=>poll());
  assert.equal(await f.page.locator('#brew-button,[data-start],#lock-label').count(),0);
  const before=f.calls.length;
  await f.page.evaluate(async()=>{for(const kind of ['espresso','flush','steam','hotwater'])await machineAction(kind)});
  assert(!f.calls.slice(before).some(c=>/machine\/(espresso|flush|steam|hotwater)/.test(c.path)));
 });
 await check('temporary recipe applies once with readback and receipt',async()=>{await f.page.locator('#recipe-dose').fill('18.5');await f.page.locator('#apply-recipe').click();await f.page.waitForFunction(()=>!state.busy);assert.equal(f.current.dose_g,18.5);assert.deepEqual(f.calls.findLast(x=>x.path==='/api/v1/profile'&&x.method==='POST').data,{dose_g:18.5});assert.equal(f.calls.filter(x=>x.path==='/api/v1/profile'&&x.method==='POST').length,1);assert(f.receiptReads>0);assert(await f.page.locator('#recipe-note').innerText())});
 await check('stage edit preserves hidden native fields and saves in order',async()=>{await f.page.locator('nav [data-page=profiles]').click();await f.page.locator('[data-field=seconds]').focus();assert(await f.page.evaluate(()=>{const el=document.activeElement;renderProfiles();return el===document.activeElement&&el.isConnected}),'refresh replaced focused pristine field');await f.page.locator('[data-field=seconds]').fill('13');await f.page.locator('#save-profile').click();await f.page.waitForFunction(()=>!state.busy);const calls=f.calls.filter(x=>x.method==='POST'&&((x.path==='/api/v1/profile'&&x.data?.steps)||x.path==='/api/v1/profile/save'));assert.deepEqual(calls.map(c=>c.path),['/api/v1/profile','/api/v1/profile/save']);assert.equal(calls[0].data.steps[0].max_flow_or_pressure_range,.4);assert.equal(calls[0].data.steps[0].popup,'保留说明');assert.equal(calls[0].data.steps[0].seconds,13)});
 await check('profile preview GET does not select; load requires a separate action',async()=>{await f.page.locator('[data-profile="中文曲线"]').click();await f.page.waitForSelector('#load-profile');assert.equal(f.current.profile,'Demo_Two_Stage');assert(!f.calls.some(x=>x.method==='PUT'));await f.page.locator('#load-profile').click();await f.page.waitForFunction(()=>!state.busy);assert.equal(f.current.profile,'中文曲线')});
 await check('download returns server file without a demo wrapper',async()=>{const before=f.calls.length;await f.page.locator('[data-profile=Demo_Two_Stage]').click();await f.page.waitForSelector('#export-profile');const event=f.page.waitForEvent('download');await f.page.locator('#export-profile').click();const d=await event;assert.equal(d.suggestedFilename(),'Demo_Two_Stage.tcl');assert.equal(fs.readFileSync(await d.path(),'utf8'),template);assert(!f.calls.slice(before).some(x=>x.method!=='GET'))});
 await check('import preview/upload is separate from current selection',async()=>{await f.page.locator('#import-button').click();await f.page.locator('#import-file').setInputFiles({name:'本地曲线.tcl',mimeType:'text/plain',buffer:Buffer.from(template)});await f.page.waitForSelector('#confirm-import');const current=f.current.profile;assert.equal(await f.page.locator('#import-filename').inputValue(),'本地曲线.tcl');await f.page.locator('#confirm-import').click();await f.page.waitForFunction(()=>!state.busy&&!document.querySelector('#dialog').open);assert(f.files['本地曲线.tcl']);assert.equal(f.current.profile,current);const call=f.calls.find(x=>x.path.endsWith('/profiles/import')&&!x.data.dry_run);assert.equal(call.data.overwrite,false)});
 await check('malformed or executable upload rejected without POST',async()=>{const before=f.calls.length;await f.page.locator('#import-button').click();await f.page.locator('#import-file').setInputFiles({name:'恶意.tcl',mimeType:'text/plain',buffer:Buffer.from(template+'\nadvanced_shot_tcl {exec do_not_run}\n')});await f.page.waitForSelector('#upload-error:not([hidden])');assert(!f.calls.slice(before).some(x=>x.method==='POST'));await f.page.locator('#dialog-actions button').click()});
 await check('favorites support empty slots and save without selecting',async()=>{await f.page.locator('#favorite-edit-button').click();await f.page.locator('[data-favorite-slot="4"]').selectOption('本地曲线');const current=f.current.profile;await f.page.locator('#dialog-actions .primary').click();await f.page.waitForFunction(()=>!state.busy);assert.equal(f.current.profile,current);assert.equal(f.calls.findLast(x=>x.path==='/api/v1/favorites'&&x.method==='POST').data.slots[4].profile,'本地曲线')});
 await check('settings apply only changed fields and read back',async()=>{await f.page.locator('nav [data-page=settings]').click();await f.page.waitForSelector('[data-setting=flushFlow]');assert((await f.page.locator('#settings-body').innerText()).includes('杯重目标未生效'));assert.equal(await f.page.locator('[data-start]').count(),0);await f.page.locator('[data-setting=flushFlow]').fill('5.5');await f.page.locator('#apply-settings').click();await f.page.waitForFunction(()=>!state.busy);assert.deepEqual(f.calls.findLast(x=>x.path==='/api/v1/controls'&&x.method==='POST').data,{flush_flow_ml_s:5.5});assert.equal(await f.page.locator('[data-setting=flushFlow]').inputValue(),'5.5')});
 await check('all setting groups expose actual values; compensation is not measured data',async()=>{for(const id of ['scale','preheat','schedule','charge','flow','shortcuts']){await f.page.locator('[data-group='+id+']').click();await f.page.waitForFunction(id=>settingsCache.has(id),id);assert((await f.page.locator('#settings-body').innerText()).trim())}assert.equal(await f.page.locator('[data-shortcut]').count(),12)});
 await check('history downloads, chart expansion and next-profile entry work',async()=>{await f.page.locator('nav [data-page=history]').click();await f.page.waitForFunction(()=>history[state.history]?.raw);assert.equal(await f.page.locator('#history-chart [data-trace]').count(),4);const event=f.page.waitForEvent('download');await f.page.locator('#download-json').click();const d=await event;assert.deepEqual(JSON.parse(fs.readFileSync(await d.path(),'utf8')),shot);await f.page.locator('[data-expand=history-chart]').click();await f.page.waitForSelector('#zoom-chart [data-trace]');assert.equal(await f.page.locator('#zoom-chart [data-trace]').count(),4);await f.page.locator('#dialog-actions button').click()});
 await check('bilingual light/dark landscape layout and footer controls remain visible',async()=>{for(const size of [{width:1024,height:600},{width:1280,height:800}]){await f.page.setViewportSize(size);for(const lang of ['zh','en']){if(await f.page.evaluate(()=>language)!==lang)await f.page.locator('#language-button').click();for(const theme of ['dark','light']){if(await f.page.evaluate(()=>theme)!==theme)await f.page.locator('#theme-button').click();for(const name of ['current','profiles','history','settings']){await f.page.locator('nav [data-page='+name+']').click();await f.page.waitForTimeout(40);const b=await f.page.locator(name==='current'?'#stop-button':name==='profiles'?'#editor-footer button:last-child':name==='history'?'#download-json':'#apply-settings').boundingBox();assert(b&&b.y+b.height<=size.height,`${name} ${lang} ${theme} bottom clipped`)}assert(await f.page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));assert(!(await f.page.locator('.local-only').innerText()).includes('Demo'));}}}});
 await check('narrow browser side panel stacks recipe and keeps readings and actions clear',async()=>{await f.page.setViewportSize({width:642,height:1314});await f.page.locator('nav [data-page=current]').click();for(const lang of ['zh','en']){if(await f.page.evaluate(()=>language)!==lang)await f.page.locator('#language-button').click();const recipe=await f.page.locator('.current-grid .recipe').boundingBox(),telemetry=await f.page.locator('.current-grid .telemetry').boundingBox(),stop=await f.page.locator('#stop-button').boundingBox();assert(recipe.y+recipe.height<=telemetry.y,'recipe overlaps chart');assert(stop.y+stop.height<=1314,'stop button clipped');const readings=await f.page.locator('.readouts .reading').evaluateAll(els=>els.map(e=>({box:e.getBoundingClientRect().toJSON(),value:e.querySelector('.value').getBoundingClientRect().toJSON(),width:e.querySelector('.value').scrollWidth})));for(const r of readings)assert(r.width<=r.box.width+1,'reading overflows its column');assert(await f.page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}await f.page.setViewportSize({width:1280,height:800})});
 await check('live stream with no target vectors never manufactures targets or breaks connection',async()=>{f.setActive('Espresso');await f.page.evaluate(()=>poll());assert.equal(await f.page.evaluate(()=>state.connected),true);assert.equal(await f.page.evaluate(()=>liveChart.rows.length),3);assert.equal(await f.page.locator('#home-chart [data-goal=pressure]').getAttribute('d'),'')});
 await check('connection loss clears live telemetry and disables starts',async()=>{await f.page.evaluate(()=>clearInterval(pollTimer));await f.page.waitForFunction(()=>!polling);f.offline();await f.page.evaluate(()=>poll());assert.equal(await f.page.evaluate(()=>state.connected),false);assert.equal(await f.page.locator('#brew-button,[data-start]').count(),0);assert((await f.page.locator('#readouts').innerText()).includes('—'))});
 await check('transport recovery clears stale connection warning without writes',async()=>{const count=f.calls.filter(x=>x.method!=='GET').length;f.online();f.setActive('Idle');await f.page.evaluate(()=>poll());assert.equal(await f.page.evaluate(()=>state.connected),true);assert(!/连接中断|Connection lost/.test(await f.page.locator('#receipt').innerText()));assert(/已连接|Connected/.test(await f.page.locator('#receipt').innerText()));assert.equal(f.calls.filter(x=>x.method!=='GET').length,count)});
 await check('transport recovery preserves a newer operation result',async()=>{f.offline();await f.page.evaluate(()=>poll());await f.page.evaluate(()=>receipt('结果暂不可确认 · 不会重复发送','warn'));f.online();await f.page.evaluate(()=>poll());assert(/结果暂不可确认|Result unknown/.test(await f.page.locator('#receipt').innerText()),await f.page.locator('#receipt').innerText());assert.equal(await f.page.evaluate(()=>state.connected),true)});
 await check('no uncaught JavaScript errors across the production paths',async()=>assert.deepEqual(f.errors,[]));await f.c.close();
 for(const [name,opts] of [['empty history',{empty:true}],['missing goals',{missingGoal:true}],['unsupported settings',{failSettings:true}]]){const g=await fixture(opts);await login(g);await check(name+' has explicit empty/unavailable states without exception',async()=>{await g.page.locator('nav [data-page=history]').click();if(opts.failSettings){await g.page.locator('nav [data-page=settings]').click();await g.page.waitForFunction(()=>!!state.settingError);assert(await g.page.locator('#apply-settings').isDisabled())}if(opts.empty)assert.equal(await g.page.locator('#download-json').isDisabled(),true);assert.deepEqual(g.errors,[])});await g.c.close()}
 const hist=await fixture({failHistory:true});await check('history failure preserves authenticated machine connection',async()=>{await hist.page.locator('#access-key').fill('test-local-token');await hist.page.locator('#dialog-actions .primary').click();await hist.page.waitForFunction(()=>state.authenticated&&!document.querySelector('#dialog').open);await hist.page.evaluate(()=>poll());assert.equal(await hist.page.evaluate(()=>state.connected),true);assert.equal(await hist.page.locator('#recipe-dose').inputValue(),'20');assert.deepEqual(hist.errors,[])});await hist.c.close();
 const fullHistory=await fixture({multipleShots:true});await login(fullHistory);
 await fullHistory.page.evaluate(()=>clearInterval(pollTimer));await fullHistory.page.waitForFunction(()=>!polling);
 await check('history fills every JSON and raw row without clicking individual shots',async()=>{
  await fullHistory.page.locator('nav [data-page=history]').click();await fullHistory.page.waitForFunction(()=>shotCache.size===4);
  assert.deepEqual(await fullHistory.page.locator('#history-list strong').allTextContents(),['合成历史样本','原生基本曲线','Second synthetic shot','合成旧格式记录']);
  assert.deepEqual(await fullHistory.page.evaluate(()=>history.map(r=>[r.dose,r.yield,r.duration])),[[20,80.9,43],[18,36,27],[19,60,32],[15,75,2]]);
  const reads=fullHistory.calls.filter(c=>/\/shots\/(json\/)?[0-9]/.test(c.path));assert.equal(reads.length,4);
  await fullHistory.page.evaluate(()=>refreshHistory());assert.equal(fullHistory.calls.filter(c=>/\/shots\/(json\/)?[0-9]/.test(c.path)).length,4);
 });
 await check('English history preserves real titles but translates loading and failed rows',async()=>{
  await fullHistory.page.locator('#language-button').click();await fullHistory.page.waitForTimeout(60);
  assert.equal(await fullHistory.page.locator('[data-history="1"] strong').innerText(),'原生基本曲线');
  await fullHistory.page.evaluate(()=>{shotCache.delete(history[1].id);renderHistory()});await fullHistory.page.waitForTimeout(60);
  assert.equal(await fullHistory.page.locator('[data-history="1"] strong').innerText(),'Loading shot…');
  await fullHistory.page.evaluate(()=>{history[1].readFailed=true;renderHistory()});await fullHistory.page.waitForTimeout(60);
  assert.equal(await fullHistory.page.locator('[data-history="1"] strong').innerText(),'Could not load this shot.');
  await fullHistory.page.locator('[data-history="1"]').click();await fullHistory.page.waitForFunction(()=>shotCache.has(history[1].id));
  assert.equal(await fullHistory.page.locator('[data-history="1"] strong').innerText(),'原生基本曲线');
 });
 await check('failed latest detail clears old home chart and label without hiding older shots',async()=>{
  fullHistory.detailFailures.add('20000102T103000.json');await fullHistory.page.evaluate(async()=>{shotCache.clear();await refreshHistory()});
  await fullHistory.page.waitForFunction(()=>shotCache.size===3);await fullHistory.page.waitForTimeout(60);
  assert.equal(await fullHistory.page.locator('#history-list [data-history]').count(),4);
  assert.equal(await fullHistory.page.locator('[data-history="0"] strong').innerText(),'Could not load this shot.');
  assert.equal(await fullHistory.page.evaluate(()=>lastShot),null);
  assert.equal(await fullHistory.page.locator('#home-chart path.native-trace').count(),0);
  assert(!(await fullHistory.page.locator('#home-chart').evaluate(el=>el.closest('.chart-panel').querySelector('.chart-head>span').textContent)).includes('2000-01-02'));
 });
 await check('explicit retry restores latest shot on both history and home without writes',async()=>{
  fullHistory.detailFailures.clear();await fullHistory.page.locator('[data-history="0"]').click();await fullHistory.page.waitForFunction(()=>!!lastShot&&shotCache.size===4);
  assert((await fullHistory.page.locator('#home-chart path.native-trace').count())>0);
  assert.equal(await fullHistory.page.locator('#history-chart-title').innerText(),'合成历史样本');
  assert(!fullHistory.calls.some(c=>c.method!=='GET'));assert.deepEqual(fullHistory.errors,[]);
 });
 await check('English key hint explains fresh installations and preserves existing keys on update',async()=>{
  await fullHistory.page.locator('#connect-button').click();await fullHistory.page.waitForTimeout(60);
  const text=await fullHistory.page.locator('.connection-help').innerText();assert(text.includes('New installations: admin1234. Updates keep your existing key.'));
 });await fullHistory.c.close();
 const pending=await fixture({holdReceipt:true});await login(pending);await check('stop remains available during a pending profile send without losing its receipt',async()=>{await pending.page.locator('#recipe-dose').fill('19');await pending.page.locator('#apply-recipe').click();await pending.page.waitForFunction(()=>state.busy&&!!state.pendingId);const id=await pending.page.evaluate(()=>state.pendingId);await pending.page.locator('#stop-button').click();await pending.page.waitForTimeout(80);assert.equal(await pending.page.evaluate(()=>state.pendingId),id);assert(pending.calls.some(x=>x.path==='/api/v1/machine/stop'));pending.release();await pending.page.waitForFunction(()=>!state.busy);assert.equal(pending.calls.filter(x=>x.path==='/api/v1/profile'&&x.method==='POST').length,1)});await pending.c.close();
 const draft=await fixture();await login(draft);await check('unapplied home recipe blocks save-as and survives polling',async()=>{await draft.page.locator('#recipe-dose').fill('18');await draft.page.evaluate(()=>refreshProfile());assert.equal(await draft.page.locator('#recipe-dose').inputValue(),'18');await draft.page.locator('nav [data-page=profiles]').click();await draft.page.locator('#save-as-profile').click();await draft.page.waitForFunction(()=>document.querySelector('#dialog').open);assert((await draft.page.locator('#dialog').innerText()).includes('参数尚未应用'));assert(!draft.calls.some(x=>x.method==='POST'));assert.deepEqual(draft.errors,[])});await draft.c.close();
 const remember=await fixture();await check('remember connection is opt-in, masked and clearly locates tablet settings',async()=>{assert.equal(await remember.page.locator('#access-key').inputValue(),'admin1234');assert.equal(await remember.page.locator('#remember-connection').isChecked(),false);assert((await remember.page.locator('.connection-help').innerText()).includes('平板'));await remember.page.locator('#show-access-key').click();assert.equal(await remember.page.locator('#access-key').getAttribute('type'),'text');await remember.page.locator('#show-access-key').click();assert.equal(await remember.page.locator('#access-key').getAttribute('type'),'password')});
 await check('remember opt-in stores only after successful login and reconnects on refresh',async()=>{await remember.page.locator('#remember-connection').check();await login(remember);assert.equal(await remember.page.evaluate(()=>localStorage.getItem('decent-remote-access-key')),'test-local-token');await remember.page.reload();await remember.page.waitForFunction(()=>state.authenticated&&!document.querySelector('#dialog').open);assert.equal(await remember.page.locator('#recipe-dose').inputValue(),'20');assert(!remember.calls.some(x=>x.method!=='GET'))});
 await check('forget connection removes the saved key and prevents automatic reconnect',async()=>{await remember.page.locator('#connect-button').click();await remember.page.getByRole('button',{name:'忘记连接',exact:true}).click();assert.equal(await remember.page.evaluate(()=>localStorage.getItem('decent-remote-access-key')),null);assert.equal(await remember.page.evaluate(()=>state.authenticated),false);const count=remember.calls.length;await remember.page.reload();await remember.page.waitForSelector('#access-key');assert.equal(remember.calls.length,count)});await remember.c.close();
 const expired=await fixture({remembered:'old-invalid-key'});await check('expired remembered key is discarded and never silently retried',async()=>{await expired.page.waitForSelector('#login-error:not(:empty)');assert.equal(await expired.page.evaluate(()=>localStorage.getItem('decent-remote-access-key')),null);assert.equal(await expired.page.locator('#remember-connection').isChecked(),false);assert.equal(expired.calls.length,1);assert(!expired.calls.some(x=>x.method!=='GET'))});await expired.c.close();
 const rotated=await fixture();await rotated.page.locator('#remember-connection').check();await login(rotated);await check('tablet key change stops old authentication and shows reconnect without device writes',async()=>{rotated.changeKey('new-test-key');await rotated.page.evaluate(()=>poll());assert.equal(await rotated.page.evaluate(()=>state.authenticated),false);assert.equal(await rotated.page.evaluate(()=>localStorage.getItem('decent-remote-access-key')),null);assert(await rotated.page.locator('#access-key').isVisible());assert((await rotated.page.locator('#login-error').innerText()).includes('密钥已变更'));assert(!rotated.calls.some(x=>x.method!=='GET'))});await rotated.c.close();
 const noStorage=await fixture({storageFailure:true});await check('storage restriction still permits current-session connection',async()=>{await noStorage.page.locator('#remember-connection').check();await login(noStorage);assert.equal(await noStorage.page.evaluate(()=>state.authenticated),true);assert.equal(await noStorage.page.evaluate(()=>localStorage.getItem('decent-remote-access-key')),null);assert((await noStorage.page.locator('#receipt').innerText()).includes('浏览器未允许'));assert.deepEqual(noStorage.errors,[])});await noStorage.c.close();
 const disconnecting=await fixture();await login(disconnecting);await check('an old poll response cannot reconnect after Forget or Disconnect',async()=>{let release,started;const gate=new Promise(r=>release=r),waiting=new Promise(r=>started=r);await disconnecting.page.route('**/api/v1/status',async r=>{started();await gate;await r.fallback()});const pending=disconnecting.page.evaluate(()=>poll());await waiting;await disconnecting.page.evaluate(()=>disconnect());release();await pending;assert.equal(await disconnecting.page.evaluate(()=>state.authenticated),false);assert.equal(await disconnecting.page.evaluate(()=>state.connected),false);assert((await disconnecting.page.locator('#readouts').innerText()).includes('—'));assert.deepEqual(disconnecting.errors,[])});await disconnecting.c.close();
 const bad=await fixture({invalidAuth:true});await check('invalid key stays at login and cannot mutate',async()=>{await bad.page.locator('#access-key').fill('bad-token');await bad.page.locator('#dialog-actions .primary').click();await bad.page.waitForSelector('#login-error:not(:empty)');assert(await bad.page.locator('#dialog').isVisible());assert(!bad.calls.some(x=>x.method!=='GET'))});await bad.c.close();
 const lost=await fixture({dropWrite:true});await login(lost);await check('lost POST response queries receipt, never retries the mutation',async()=>{await lost.page.locator('#recipe-dose').fill('19');await lost.page.locator('#apply-recipe').click();await lost.page.waitForFunction(()=>!state.busy);assert.equal(lost.calls.filter(x=>x.path==='/api/v1/profile'&&x.method==='POST').length,1);assert.equal(await lost.page.locator('#recipe-dose').inputValue(),'19')});await lost.c.close();
 const u=await fixture({unconfirmed:true});await login(u);await check('unconfirmed stage apply stops automatic save chain',async()=>{await u.page.locator('nav [data-page=profiles]').click();await u.page.locator('[data-field=seconds]').fill('14');await u.page.locator('[data-field=seconds]').dispatchEvent('change');await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);assert(!u.calls.some(x=>x.path==='/api/v1/profile/save'));assert((await u.page.locator('#receipt').innerText()).includes('尚未确认'))});
 const profileWrites=f=>f.calls.filter(x=>x.method==='POST'&&x.path.startsWith('/api/v1/profile')).map(x=>x.path);
 async function submitSaveAs(f){await f.page.locator('#save-as-profile').click();await f.page.locator('#dialog-actions .primary').click();await f.page.waitForFunction(()=>!state.busy&&!document.querySelector('#dialog').open)}
 await check('repeated save after readback and navigation cannot bypass missing device confirmation',async()=>{
  await u.page.locator('nav [data-page=current]').click();await u.page.evaluate(()=>refreshProfile());await u.page.locator('nav [data-page=profiles]').click();
  const before=profileWrites(u);await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);
  assert.deepEqual(profileWrites(u),before);assert.equal(await u.page.locator('#editor-badge').innerText(),'设备尚未确认');
  assert.equal(await u.page.locator('#apply-profile').innerText(),'重新发送');assert.equal(await u.page.locator('#apply-profile').isDisabled(),false);
 });
 await check('save-as after unconfirmed apply cannot create a file',async()=>{
  const before=profileWrites(u),files=Object.keys(u.files);await submitSaveAs(u);
  assert.deepEqual(profileWrites(u),before);assert.deepEqual(Object.keys(u.files),files);assert((await u.page.locator('#receipt').innerText()).includes('尚未确认'));
 });
 await check('page reload cannot turn App readback into a device confirmation',async()=>{
  const before=profileWrites(u);await u.page.reload();await login(u);await u.page.locator('nav [data-page=profiles]').click();
  await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);await submitSaveAs(u);
  assert.deepEqual(profileWrites(u),before);assert.equal(await u.page.locator('#editor-badge').innerText(),'已读取');assert.equal(await u.page.evaluate(()=>needsProfileConfirmation()),true);
 });
 await check('reverting an edit to the unconfirmed values never resends through Save or Save as',async()=>{
  const before=copy(u.calls.filter(x=>x.method==='POST'));await u.page.locator('[data-field=seconds]').fill('15');await u.page.locator('[data-field=seconds]').fill('14');
  assert.equal(await u.page.evaluate(()=>state.dirty),false);assert.equal(await u.page.locator('#apply-profile').innerText(),'重新发送');
  await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);await submitSaveAs(u);
  assert.deepEqual(u.calls.filter(x=>x.method==='POST'),before);
 });
 await check('only an explicit confirmed resend enables saving the same applied edit',async()=>{
  const before=profileWrites(u).length;u.confirm(true);await u.page.locator('#apply-profile').click();await u.page.waitForFunction(()=>!state.busy);
  assert.deepEqual(profileWrites(u).slice(before),['/api/v1/profile']);assert.equal(await u.page.locator('#editor-badge').innerText(),'已应用 · 未保存');
  await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);
  assert.deepEqual(profileWrites(u).slice(before),['/api/v1/profile','/api/v1/profile/save']);assert.equal(u.current.dirty,false);assert.equal(await u.page.evaluate(()=>needsProfileConfirmation()),false);
 });
 await check('confirmation for an earlier edit cannot authorize a later unconfirmed edit',async()=>{
  u.confirm(false);const before=profileWrites(u).length;await u.page.locator('[data-field=seconds]').fill('15');await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);
  await u.page.locator('#save-profile').click();await u.page.waitForFunction(()=>!state.busy);await submitSaveAs(u);
  assert.deepEqual(profileWrites(u).slice(before),['/api/v1/profile']);assert.equal(u.current.dirty,true);assert.deepEqual(u.errors,[]);
 });await u.c.close();
 const recipeUnconfirmed=await fixture({unconfirmed:true});await login(recipeUnconfirmed);
 await check('unconfirmed recipe changes block both profile save paths without resending',async()=>{
  await recipeUnconfirmed.page.locator('#recipe-dose').fill('18');await recipeUnconfirmed.page.locator('#apply-recipe').click();await recipeUnconfirmed.page.waitForFunction(()=>!state.busy);
  await recipeUnconfirmed.page.locator('nav [data-page=profiles]').click();await recipeUnconfirmed.page.locator('#save-profile').click();await recipeUnconfirmed.page.waitForFunction(()=>!state.busy);await submitSaveAs(recipeUnconfirmed);
  assert.deepEqual(profileWrites(recipeUnconfirmed),['/api/v1/profile']);assert.equal(recipeUnconfirmed.calls.filter(x=>x.method==='POST'&&x.path==='/api/v1/profile').length,1);
  assert.equal(await recipeUnconfirmed.page.locator('#editor-badge').innerText(),'设备尚未确认');assert.deepEqual(recipeUnconfirmed.errors,[]);
 });await recipeUnconfirmed.c.close();
 for(const [mode,clean] of [['stage',false],['recipe',false],['stage',true],['recipe',true]]){
  const race=await fixture({externalAfterAck:true,externalClean:clean});await login(race);
  await check(mode+(clean?' saved':' unsaved')+' external readback cannot inherit a different confirmation',async()=>{
   if(mode==='stage'){await race.page.locator('nav [data-page=profiles]').click();await race.page.locator('[data-field=seconds]').fill('14');await race.page.locator('#apply-profile').click()}
   else{await race.page.locator('#recipe-dose').fill('18');await race.page.locator('#apply-recipe').click()}
   await race.page.waitForFunction(()=>!state.busy);await race.page.locator('nav [data-page=profiles]').click();
   assert.equal(race.current.steps[0].seconds,99);assert.equal(await race.page.evaluate(()=>needsProfileConfirmation()),true);
   assert.equal(await race.page.locator('#editor-badge').innerText(),'设备尚未确认');assert((await race.page.locator('#receipt').innerText()).includes('未获得对应确认'));
   const before=copy(race.calls.filter(x=>x.method==='POST'));if(!clean){await race.page.locator('#save-profile').click();await race.page.waitForFunction(()=>!state.busy)}await submitSaveAs(race);
   assert.deepEqual(race.calls.filter(x=>x.method==='POST'),before);
   // Reload must preserve a known mismatch even when another client saved the file.
   await race.page.reload();await login(race);await race.page.locator('nav [data-page=profiles]').click();
   assert.equal(await race.page.evaluate(()=>needsProfileConfirmation()),true);await submitSaveAs(race);
   assert.deepEqual(race.calls.filter(x=>x.method==='POST'),before);assert.deepEqual(race.errors,[]);
  });await race.c.close();
 }
 for(const unavailable of [false,true]){
  const fresh=await fixture({sessionFailure:unavailable});await login(fresh);
  await check('fresh page does not infer confirmation from clean App state; session storage '+(unavailable?'blocked':'available'),async()=>{
   await fresh.page.locator('nav [data-page=profiles]').click();await submitSaveAs(fresh);
   assert(!fresh.calls.some(x=>x.method!=='GET'));assert.equal(await fresh.page.evaluate(()=>needsProfileConfirmation()),true);
   await fresh.page.locator('#apply-profile').click();await fresh.page.waitForFunction(()=>!state.busy);
   assert.equal(await fresh.page.evaluate(()=>needsProfileConfirmation()),false);await submitSaveAs(fresh);
   assert(fresh.calls.some(x=>x.path==='/api/v1/profile/save-as'));
   const before=copy(fresh.calls.filter(x=>x.method==='POST'));
   await fresh.page.reload();await login(fresh);await fresh.page.locator('nav [data-page=profiles]').click();
   await fresh.page.locator('#save-as-profile').click();await fresh.page.locator('#new-filename').fill('second-copy.tcl');await fresh.page.locator('#dialog-actions .primary').click();await fresh.page.waitForFunction(()=>!state.busy&&!document.querySelector('#dialog').open);
   assert.deepEqual(fresh.calls.filter(x=>x.method==='POST'),before);assert.deepEqual(fresh.errors,[]);
  });await fresh.c.close();
 }
 await browser.close();console.log(JSON.stringify({passed,failed:failures.length,failures,network:'All requests intercepted. No device traffic.',scope:'Production client, actual HTML, exact sample chart, native API contract'},null,2));process.exitCode=failures.length?1:0;
})().catch(e=>{console.error(e);process.exitCode=1});
