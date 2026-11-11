let language='en',data=null,failed=false,product='all';
const $=id=>document.getElementById(id);
const words={
  en:{title:'Used around the world',intro:'Country and region totals for reporting installations.',product:'Product',all:'All products',this_cup:'This Cup',total:'Installations counted',active:'Active in 30 days',regions:'Countries / regions',country:'Country / region',count:'Total',recent:'Active · 30d',pending:'Statistics are not available yet.',categoryPending:'Statistics for this product are not available yet.',legacy:'This snapshot covers Decent Remote only. This Cup statistics are not available yet.',empty:'No installations have been counted for this selection yet.',failed:'Statistics could not be loaded. Please try again later.',updated:'Updated',note:'Counts represent installations, not people or physical devices. Each product is counted separately. VPNs, browser storage and reinstalls can affect the figures.',unknown:'Unknown'},
  zh:{title:'各地都在用',intro:'按国家和地区汇总已上报的安装数量。',product:'分类',all:'全部',this_cup:'这一杯',total:'已统计安装',active:'近 30 天活跃',regions:'国家／地区',country:'国家／地区',count:'安装数',recent:'近 30 天活跃',pending:'统计暂未上线。',categoryPending:'该分类的统计暂未上线。',legacy:'当前快照仅包含 Decent Remote；这一杯分类暂未上线。',empty:'这个分类目前还没有安装统计。',failed:'暂时无法读取统计，请稍后再试。',updated:'更新于',note:'统计的是安装数量，不是人数或实体设备数；不同产品分别计数。VPN、浏览器存储和重新安装可能影响结果。',unknown:'未知'}
};
function validTotals(value){
  return value&&Number.isInteger(value.total_installations)&&value.total_installations>=0&&Number.isInteger(value.active_30d)&&value.active_30d>=0&&value.active_30d<=value.total_installations&&Array.isArray(value.countries)&&value.countries.every(r=>r&&/^[A-Z]{2}$/.test(r.country)&&Number.isInteger(r.installations)&&r.installations>=0&&Number.isInteger(r.active_30d)&&r.active_30d>=0&&r.active_30d<=r.installations);
}
function selection(){
  if(product==='all')return data;
  if(data.schema===1)return product==='decent_remote'?data:null;
  return data.products.find(row=>row.product===product);
}
function render(){
  const w=words[language];
  document.documentElement.lang=language==='en'?'en':'zh-CN';
  $('language').textContent=language==='en'?'中文':'English';
  $('title').textContent=w.title;
  $('intro').textContent=w.intro;
  $('product-label').textContent=w.product;
  $('product').options[0].textContent=w.all;
  $('product').options[2].textContent=w.this_cup;
  for(const [id,key]of Object.entries({'total-label':'total','active-label':'active','regions-label':'regions','country-label':'country','count-label':'count','recent-label':'recent','note':'note'}))$(id).textContent=w[key];
  $('rows').replaceChildren();$('table').hidden=true;$('updated').textContent='';
  for(const id of ['total','active','regions'])$(id).textContent='—';
  if(failed){$('message').textContent=w.failed;return}
  if(!data||data.status==='not_deployed'){$('message').textContent=w.pending;return}
  const selected=selection();
  if(!selected){$('message').textContent=w.categoryPending;return}
  $('total').textContent=selected.total_installations.toLocaleString();
  $('active').textContent=selected.active_30d.toLocaleString();
  $('regions').textContent=selected.countries.filter(r=>r.country!=='ZZ'&&r.installations>0).length;
  $('message').textContent=data.schema===1?w.legacy:selected.countries.length?'':w.empty;
  $('table').hidden=!selected.countries.length;
  let names;try{names=new Intl.DisplayNames([language],{type:'region'})}catch{}
  const max=Math.max(1,...selected.countries.map(r=>r.installations));
  for(const r of selected.countries){
    const tr=document.createElement('tr'),name=document.createElement('td'),total=document.createElement('td'),active=document.createElement('td');
    name.textContent=r.country==='ZZ'?w.unknown:(names?.of(r.country)||r.country);
    const bar=document.createElement('div'),fill=document.createElement('i');
    bar.className='bar';fill.style.width=(100*r.installations/max)+'%';bar.append(fill);name.append(bar);
    total.textContent=r.installations.toLocaleString();active.textContent=r.active_30d.toLocaleString();tr.append(name,total,active);$('rows').append(tr);
  }
  $('updated').textContent=w.updated+' '+new Date(data.generated_at).toLocaleString(language==='en'?'en-GB':'zh-CN');
}
$('language').onclick=()=>{language=language==='en'?'zh':'en';render()};
$('product').onchange=()=>{product=$('product').value;render()};
render();
async function readSummary(url){const response=await fetch(url,{cache:'no-store',signal:AbortSignal.timeout(8000)});if(!response.ok)throw Error('unavailable');return response.json()}
readSummary('https://decent-remote-usage.decent-remote-stats.workers.dev/v2/summary').catch(()=>readSummary('./data.json')).then(d=>{
  if(d.status!=='not_deployed'){
    if(![1,2].includes(d.schema)||!validTotals(d))throw Error('invalid');
    if(d.schema===2&&(!Array.isArray(d.products)||d.products.length!==2||!['decent_remote','this_cup'].every(p=>d.products.filter(r=>r.product===p&&validTotals(r)).length===1)))throw Error('invalid');
  }
  data=d;render();
}).catch(()=>{failed=true;render()});
