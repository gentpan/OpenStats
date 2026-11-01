import Foundation

/// 监控大屏页面：一个自包含的 HTML 文件（无外部依赖），由 DashboardServer 直接下发。
/// 每 2 秒拉一次 /metrics；断网时保留最后读数并持续重试。数据源没有 Gost 线路时自动收起该卡片。
/// 布局自适应三种形态：横屏（≥4:3）、竖屏平板（宽≥1000px）、窄屏手机
enum DashboardPage {
    static let html = Data(#"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>主机监控</title>
<style>
:root{color-scheme:dark;--bg:#0b1018;--card:#131c28;--inset:#0d1520;--border:#263447;--text:#eaf1fa;--muted:#a0afc1;--cyan:#58c8fa;--purple:#b49aff;--green:#61da95;--amber:#ffc369;--red:#ff8188;--orange:#ffb080;--font:14px;--number:38px;--pad:14px;--gap:10px;--gost-min:290px}
*{box-sizing:border-box}html,body{margin:0;min-height:100%;width:100%}body{height:100vh;padding:12px;display:grid;grid-template-rows:auto minmax(0,1fr) auto;grid-gap:10px;background:var(--bg);color:var(--text);font:var(--font)/1.35 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;font-variant-numeric:tabular-nums;overflow:auto}
header{display:grid;grid-template-columns:14px minmax(0,1fr) auto;grid-gap:12px;align-items:center;padding:12px 16px;border-bottom:1px solid var(--border)}.host{font-size:21px;font-weight:700;overflow-wrap:anywhere}.ip,.uptime{color:var(--muted);font-size:var(--font)}.clock{font-size:29px;font-weight:700;line-height:1.2;text-align:right}.uptime{text-align:right;margin-top:4px}.connection{color:var(--green);margin-top:3px;font-size:var(--font);overflow-wrap:anywhere}.connection.warn{color:var(--amber)}.connection.off{color:var(--red)}.dot{width:11px;height:11px;border-radius:50%;background:var(--green);box-shadow:0 0 10px #61da9540}.dot.warn{background:var(--amber)}.dot.off{background:var(--red);box-shadow:0 0 10px #ff818840}
.grid{min-width:0;min-height:0;display:grid;grid-gap:var(--gap);grid-template-columns:repeat(2,minmax(0,1fr));grid-template-areas:"cpu mem" "network network" "gost gost" "system processes";grid-template-rows:minmax(180px,1fr) minmax(150px,.8fr) minmax(var(--gost-min),1.55fr) minmax(260px,1.3fr)}
.card{min-width:0;min-height:0;padding:var(--pad);border:1px solid var(--border);border-radius:12px;background:var(--card);display:flex;flex-direction:column}.cpu-card{grid-area:cpu}.memory-card{grid-area:mem}.network-card{grid-area:network}.gost-card{grid-area:gost}.system-card{grid-area:system}.process-card{grid-area:processes}
h2{margin:0 0 8px;font-size:var(--font);line-height:1.3;font-weight:650;letter-spacing:.04em;display:grid;grid-template-columns:auto minmax(0,1fr);grid-gap:8px;align-items:baseline}.hint{font-size:12px;color:var(--muted);font-weight:400;letter-spacing:0;text-align:right}.row{display:flex;flex-wrap:wrap;align-items:baseline}.big{font-size:var(--number);font-weight:700;line-height:1.1;letter-spacing:-.025em;white-space:nowrap}.sub{color:var(--muted);font-size:var(--font);overflow-wrap:anywhere}.value-sub{margin-left:10px}.cores{display:grid;grid-template-columns:repeat(8,minmax(0,1fr));grid-gap:4px;margin:9px 0 6px}.core{height:8px;border-radius:2px;background:#28374a}.core i{display:block;height:100%;border-radius:2px}.chart{position:relative;min-height:24px;flex:1;margin-top:7px}.chart canvas{position:absolute;top:0;left:0}.spark{display:block;width:100%;height:100%;min-height:24px}.chart-range{display:flex;justify-content:space-between;color:var(--muted);font-size:12px;margin-top:3px}.metric2{min-height:0;flex:1;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));grid-gap:20px}.network-metric{min-width:0;display:flex;flex-direction:column}.network-metric+.network-metric{border-left:1px solid var(--border);padding-left:20px}.rate{display:flex;flex-wrap:wrap;align-items:baseline;line-height:1.1;margin-top:3px}.rate-number{font-size:var(--number);font-weight:700;letter-spacing:-.025em}.unit{font-size:17px;font-weight:500;margin-left:5px;white-space:nowrap}.network-metric .chart{margin-top:8px}
.summary{display:grid;grid-template-columns:auto minmax(0,1fr);align-items:baseline;grid-gap:12px;margin-bottom:5px}.summary .big{font-size:30px}.summary-note{text-align:right;color:var(--muted)}.gost-processes{margin-bottom:9px;line-height:1.4;overflow-wrap:anywhere}.tiles{flex:1;min-height:0;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));grid-auto-rows:minmax(80px,1fr);grid-gap:8px}.tile{min-width:0;min-height:0;padding:9px 11px;background:var(--inset);border:1px solid var(--border);border-radius:8px;display:grid;grid-template-rows:auto auto minmax(16px,1fr);grid-gap:3px}.tile-name{display:grid;grid-template-columns:auto minmax(0,1fr);grid-gap:7px;align-items:center;font-size:var(--font);color:var(--muted)}.address{overflow-wrap:anywhere}.badge{padding:1px 5px;border:1px solid #334258;border-radius:4px;font-size:11px;color:var(--muted)}.tile-result{display:flex;justify-content:space-between;align-items:baseline;flex-wrap:wrap}.ms{font-size:28px;font-weight:700;line-height:1.1}.ms .unit{font-size:14px}.probe-age{font-size:12px;color:var(--muted);margin-left:6px}.tile canvas{display:block;width:100%;height:100%;min-height:16px}.empty{color:var(--muted);align-self:center;grid-column:1/-1;padding:16px;text-align:center}.green{color:var(--green)}.amber{color:var(--amber)}.red{color:var(--red)}.cyan{color:var(--cyan)}.orange{color:var(--orange)}.muted{color:var(--muted)}
.system-rows{display:grid;grid-template-rows:repeat(4,minmax(0,1fr));flex:1;min-height:0}.sysrow{display:grid;grid-template-columns:auto minmax(0,1fr);grid-gap:10px;align-content:center;padding:8px 0;border-bottom:1px solid var(--border)}.sysrow:last-child{border:0}.sysrow .value{text-align:right;overflow-wrap:anywhere}.table-head,.proc{display:grid;grid-template-columns:minmax(0,1fr) 70px 52px;grid-gap:5px;align-items:center}.table-head{color:var(--muted);font-size:12px;padding-bottom:5px;border-bottom:1px solid var(--border)}.table-head span:not(:first-child),.proc .val{text-align:right}.top{flex:1;min-height:0;display:grid;grid-auto-rows:minmax(27px,1fr)}.proc{padding:5px 0;border-bottom:1px solid #223044;font-size:var(--font)}.proc:last-child{border:0}.proc .name{min-width:0;overflow-wrap:anywhere;line-height:1.3}.proc .val{white-space:nowrap}.proc .name small{display:block;color:var(--muted);font-size:11px}footer{display:flex;justify-content:space-between;flex-wrap:wrap;font-size:12px;color:var(--muted);line-height:1.4;padding:0 3px}
@media(min-width:1000px) and (max-aspect-ratio:1/1){:root{--font:20px;--number:56px;--pad:22px;--gap:16px;--gost-min:420px}body{padding:20px;grid-gap:16px}header{padding:18px 22px}.host{font-size:30px}.clock{font-size:42px}.hint,.chart-range,.probe-age,.table-head,footer{font-size:16px}h2{margin-bottom:12px}.grid{grid-template-rows:minmax(240px,1fr) minmax(210px,.85fr) minmax(var(--gost-min),1.5fr) minmax(355px,1.3fr)}.cores{grid-gap:6px;margin:13px 0 9px}.core{height:12px}.summary .big{font-size:42px}.tiles{grid-gap:12px;grid-auto-rows:minmax(115px,1fr)}.tile{padding:14px 16px}.ms{font-size:42px}.badge{font-size:15px}.unit,.ms .unit{font-size:20px}.table-head,.proc{grid-template-columns:minmax(0,1fr) 92px 74px}.proc{padding:8px 0}.proc .name small{font-size:14px}}
@media(min-aspect-ratio:4/3){.grid{grid-template-columns:repeat(3,minmax(0,1fr));grid-template-areas:"cpu mem network" "gost gost gost" "system processes processes";grid-template-rows:minmax(170px,1fr) minmax(180px,1fr) minmax(225px,1.2fr)}.tiles{grid-template-columns:repeat(4,minmax(0,1fr))}.gost-processes{margin-bottom:5px}.network-metric+.network-metric{padding-left:10px}.metric2{grid-gap:10px}.rate-number{font-size:32px}.unit{font-size:14px}}
body.no-gost .grid{grid-template-areas:"cpu mem" "network network" "system processes";grid-template-rows:minmax(180px,1fr) minmax(150px,.8fr) minmax(260px,1.3fr)}
body.no-gost .gost-card{display:none}
@media(min-width:1000px) and (max-aspect-ratio:1/1){body.no-gost .grid{grid-template-rows:minmax(240px,1fr) minmax(210px,.85fr) minmax(355px,1.3fr)}}
@media(min-aspect-ratio:4/3){body.no-gost .grid{grid-template-areas:"cpu mem network" "system processes processes";grid-template-rows:minmax(170px,1fr) minmax(225px,1.2fr)}}
@media(max-width:540px){body.no-gost .grid{grid-template-areas:"cpu" "mem" "network" "system" "processes";grid-template-rows:200px 200px 190px 250px 300px}}
@media(max-width:540px){body{height:auto;min-height:100vh}.grid{grid-template-columns:1fr;grid-template-areas:"cpu" "mem" "network" "gost" "system" "processes";grid-template-rows:200px 200px 190px minmax(290px,auto) 250px 300px}header{grid-template-columns:10px minmax(0,1fr);padding:8px}.clock-block{grid-column:2;text-align:left}.clock,.uptime{text-align:left}.host{font-size:19px}.table-head,.proc{grid-template-columns:minmax(0,1fr) 65px 60px}}
</style>
</head>
<body>
<header>
 <div class="dot warn" id="dot" aria-hidden="true"></div>
 <div><div class="host" id="host">主机监控</div><div class="ip" id="ip">等待首次采样</div><div class="connection warn" id="stale" role="status">连接中…</div></div>
 <div class="clock-block"><div class="clock" id="clock">--:--:--</div><div class="uptime" id="uptime">已运行 —</div></div>
</header>
<main class="grid" id="dashboard">
 <section class="card cpu-card"><h2>CPU <span class="hint">使用率 · 0–100%</span></h2><div class="row"><div class="big" id="cpu">--</div></div><div class="sub" id="loadavg">负载 —</div><div class="cores" id="cores" aria-label="各逻辑核心使用率"></div><div class="chart"><canvas class="spark" id="cpuSpark" role="img" aria-label="CPU近5分钟使用率走势"></canvas></div><div class="chart-range"><span>5分钟前</span><span>现在</span></div></section>
 <section class="card memory-card"><h2>内存 <span class="hint">使用率 · 0–100%</span></h2><div class="row"><div class="big" id="mem">--</div><div class="sub value-sub" id="memPct">—</div></div><div class="sub" id="swap">交换 —</div><div class="chart"><canvas class="spark" id="memSpark" role="img" aria-label="内存近5分钟使用率走势"></canvas></div><div class="chart-range"><span>5分钟前</span><span>现在</span></div></section>
 <section class="card network-card"><h2>网络 <span class="hint">物理接口流量 · 近5分钟</span></h2><div class="metric2"><div class="network-metric"><div class="sub">↓ 下载</div><div class="rate cyan" id="netDown"><span class="rate-number">--</span><span class="unit">B/s</span></div><div class="chart"><canvas class="spark" id="netDownSpark" role="img" aria-label="下载速率走势"></canvas></div></div><div class="network-metric"><div class="sub">↑ 上传</div><div class="rate orange" id="netUp"><span class="rate-number">--</span><span class="unit">B/s</span></div><div class="chart"><canvas class="spark" id="netUpSpark" role="img" aria-label="上传速率走势"></canvas></div></div></div><div class="chart-range"><span>上下行共用刻度</span><span id="netScale">峰值 —</span></div></section>
 <section class="card gost-card"><h2>Gost 线路 <span class="hint">代理出口连通性 · 延迟走势</span></h2><div class="summary"><div class="big" id="gostSummary">查找中…</div><div class="summary-note" id="gostBest">—</div></div><div class="sub gost-processes" id="gostProc">等待进程及端口发现</div><div class="tiles" id="tiles"></div></section>
 <section class="card system-card"><h2>系统 <span class="hint">当前状态</span></h2><div class="system-rows"><div class="sysrow"><span class="muted">磁盘</span><span class="value" id="disk">--</span></div><div class="sysrow"><span class="muted">负载</span><span class="value" id="load2">--</span></div><div class="sysrow"><span class="muted">电池</span><span class="value" id="battery">--</span></div><div class="sysrow"><span class="muted">进程</span><span class="value" id="procs">--</span></div></div></section>
 <section class="card process-card"><h2>进程 TOP <span class="hint">按CPU排序 · 单核口径</span></h2><div class="table-head"><span>进程</span><span>CPU</span><span>内存</span></div><div class="top" id="top"></div></section>
</main>
<footer><span>OpenStats 监控大屏 · 每 2 秒自动刷新</span><span><span id="viewportSize"></span> · <span id="freshness">等待数据</span></span></footer>
<script>
'use strict';
const $=id=>document.getElementById(id);
let lastData=null,lastOkAt=0,lastSampleStamp=null,lastSampleSeenAt=0,sampleBaseAge=0,fetchFailed=false;
const escapeHTML=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function byteParts(n){n=Number.isFinite(n)?Math.max(0,n):0;for(const item of [[2**30,'GB'],[2**20,'MB'],[2**10,'KB']]){if(n>=item[0])return[(n/item[0]).toFixed(item[0]===2**10?0:1),item[1]];}return[Math.round(n)+'','B'];}
function fmtBytes(n){const p=byteParts(n);return p[0]+' '+p[1];}
function fmtUptime(s){const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return d>0?`${d}天 ${h}小时`:(h>0?`${h}小时 ${m}分`:`${m}分`);}
function msColor(ms){return ms<300?'green':ms<800?'amber':'red';}
function updateStatus(){
 $('viewportSize').textContent=innerWidth+'×'+innerHeight;
 const now=Date.now();$('clock').textContent=new Date(now).toLocaleTimeString('zh-CN',{hour12:false});
 const age=lastSampleSeenAt?Math.max(0,sampleBaseAge+(now-lastSampleSeenAt)/1000):null;
 const disconnected=fetchFailed||(lastOkAt&&now-lastOkAt>6500);
 const stale=age!==null&&age>8;
 let text='实时 · 每2秒刷新',state='live';
 if(!lastOkAt){text=fetchFailed?'连接失败 · 正在重试…':'连接中…';state=fetchFailed?'offline':'waiting';}
 else if(disconnected){text='连接中断 · 正在重试 · 保留上次读数';state='offline';}
 else if(stale){text='采样已过期 · 保留上次读数';state='stale';}
 $('stale').textContent=text;$('stale').className='connection'+(state==='offline'?' off':state==='live'?'':' warn');
 $('dot').className='dot'+(state==='offline'?' off':state==='live'?'':' warn');
 document.body.dataset.connection=state;
 $('freshness').textContent=age===null?'等待数据':`采样于 ${Math.floor(age)}秒前`;
 document.body.dataset.sampleAge=age===null?'':age.toFixed(1);
}
function spark(canvas,values,color,opts={}){
 const ctx=canvas.getContext('2d'),dpr=window.devicePixelRatio||1,w=canvas.clientWidth,h=canvas.clientHeight;
 if(!ctx||!w||!h)return;canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);ctx.scale(dpr,dpr);ctx.clearRect(0,0,w,h);
 ctx.strokeStyle='#29374a';ctx.lineWidth=.5;[.25,.5,.75].forEach(p=>{ctx.beginPath();ctx.moveTo(0,h*p);ctx.lineTo(w,h*p);ctx.stroke();});
 if(!values||values.length<2)return;
 const nums=values.filter(v=>typeof v==='number'&&Number.isFinite(v)),max=opts.max!=null?opts.max:Math.max(...nums,1);
 const x=i=>1+i/(values.length-1)*(w-2),y=v=>h-2-Math.min(Math.max(v,0),max)/max*(h-5);
 let drawing=false;ctx.beginPath();values.forEach((v,i)=>{if(typeof v!=='number'||!Number.isFinite(v)){drawing=false;return;}if(drawing)ctx.lineTo(x(i),y(v));else{ctx.moveTo(x(i),y(v));drawing=true;}});ctx.strokeStyle=color;ctx.lineWidth=1.8;ctx.stroke();
 if(opts.fill!==false&&nums.length===values.length){ctx.lineTo(x(values.length-1),h);ctx.lineTo(x(0),h);ctx.closePath();const grad=ctx.createLinearGradient(0,0,0,h);grad.addColorStop(0,color+'38');grad.addColorStop(1,color+'00');ctx.fillStyle=grad;ctx.fill();}
}
function portKey(p){return 'tile-'+String(p.address+'-'+p.port).replace(/[^a-zA-Z0-9-]/g,'_');}
function tileHTML(p,serverTime){
 const age=p.probedAt?Math.max(0,serverTime-p.probedAt):null,old=age!==null&&age>60;
 const address=p.address==='0.0.0.0'?'所有接口':p.address;
 const value=old?'已过期':p.state==='ok'?`${Math.round(p.ms)}<span class="unit">ms</span>`:p.state==='failed'?'不通':'探测中';
 const color=old?'amber':p.state==='ok'?msColor(p.ms):p.state==='failed'?'red':'muted';
 return `<div class="tile"><div class="tile-name"><span class="badge">${escapeHTML(p.kind||'—')}</span><span class="address">${escapeHTML(address)}:${escapeHTML(p.port)}</span></div><div class="tile-result"><span class="ms ${color}">${value}</span><span class="probe-age">${age===null?'等待探测':Math.floor(age)+'秒前'}</span></div><canvas id="${portKey(p)}" role="img" aria-label="端口${escapeHTML(p.port)}延迟走势，断线处留空"></canvas></div>`;
}
function rates(values,times,interval){return values.slice(1).map((v,i)=>{const dt=times&&times.length===values.length?times[i+1]-times[i]:interval;return dt>0?Math.max(0,v-values[i])/dt:0;});}
function rateValue(id,value){const parts=byteParts(value);$(id).innerHTML=`<span class="rate-number">${parts[0]}</span><span class="unit">${parts[1]}/s</span>`;}
function drawCharts(payload){
 const h=payload.history,g=payload.gost;
 spark($('cpuSpark'),h.cpu,'#58c8fa',{max:100});spark($('memSpark'),h.mem,'#b49aff',{max:100});
 const down=rates(h.netDown,h.time,payload.sampleInterval||2),up=rates(h.netUp,h.time,payload.sampleInterval||2),peak=Math.max(...down,...up,1024);
 spark($('netDownSpark'),down,'#58c8fa',{max:peak});spark($('netUpSpark'),up,'#ffb080',{max:peak});
 $('netScale').textContent='峰值 '+fmtBytes(peak)+'/s';
 if(down.length)rateValue('netDown',down[down.length-1]);if(up.length)rateValue('netUp',up[up.length-1]);
 g.ports.forEach(p=>{const canvas=$(portKey(p));if(canvas)spark(canvas,p.history,p.state==='ok'?'#61da95':'#ff8188',{fill:false});});
}
function render(payload){
 const s=payload.system,g=payload.gost||{running:false,ports:[],processes:[],upCount:0,totalPorts:0,bestMs:null};
 if(!s||!Number.isFinite(s.time)||!Array.isArray(s.cpuPercpu)||!Array.isArray(s.processes)||!payload.history)throw new Error('Incomplete metrics');
 // 数据源没有 Gost 线路（如未启用）时收起整块
 document.body.classList.toggle('no-gost',!payload.gost);
 $('host').textContent=s.hostname||'Mac';$('ip').textContent=location.hostname+' · 采样 '+new Date(s.time*1000).toLocaleTimeString('zh-CN',{hour12:false});$('uptime').textContent='已运行 '+fmtUptime(s.uptimeSec);
 $('cpu').textContent=s.cpu.toFixed(0)+'%';$('loadavg').textContent='负载 '+s.load.join(' / ');
 if($('cores').children.length!==s.cpuPercpu.length)$('cores').innerHTML=s.cpuPercpu.map(()=>'<div class="core"><i></i></div>').join('');
 s.cpuPercpu.forEach((v,i)=>{const el=$('cores').children[i];el.title=`核心${i+1}：${v}%`;el.setAttribute('aria-label',el.title);el.firstChild.style.width=Math.min(v,100)+'%';el.firstChild.style.background=v<50?'var(--cyan)':v<85?'var(--amber)':'var(--red)';});
 $('mem').textContent=s.memUsedGB.toFixed(1)+' GB';$('memPct').textContent=s.memPercent.toFixed(0)+'% / '+s.memTotalGB+' GB';$('swap').textContent='交换 '+s.swapPercent+'%';
 const healthy=g.upCount===g.totalPorts&&g.totalPorts>0;
 $('gostSummary').innerHTML=g.totalPorts?`<span class="${healthy?'green':g.upCount?'amber':'red'}">${g.upCount}/${g.totalPorts}</span><span class="unit">端口可用</span>`:g.running?'无监听端口':'未运行';
 $('gostBest').textContent=g.bestMs!=null?'最快 '+Math.round(g.bestMs)+' ms':'暂无可用线路';
 $('gostProc').textContent=g.processes.length?g.processes.length+'个进程 · '+g.processes.map(p=>`PID ${p.pid}（${p.cpu}% · ${p.memMB} MB）`).join(' · '):'本机没有名为 gost 的进程';
 const serverTime=Number.isFinite(payload.serverTime)?payload.serverTime:s.time;
 $('tiles').innerHTML=g.ports.length?g.ports.map(p=>tileHTML(p,serverTime)).join(''):'<div class="empty">没有可监控的监听端口</div>';
 const wide=matchMedia('(min-width:1000px) and (max-aspect-ratio:1/1)').matches;
 document.documentElement.style.setProperty('--gost-min',Math.max(wide?420:290,Math.ceil(g.ports.length/2)*(wide?115:85)+(wide?145:115))+'px');
 $('disk').textContent=`${s.diskUsedGB} / ${s.diskTotalGB} GB（${s.diskPercent}%）`;$('load2').textContent=s.load.join(' / ');$('battery').textContent=s.batteryPercent!=null?s.batteryPercent+'%':'—（台式机）';$('procs').textContent=s.processes.length?'CPU前'+s.processes.length+'项见进程表':'暂无进程数据';
 $('top').innerHTML=s.processes.length?s.processes.map(p=>`<div class="proc"><span class="name" title="${escapeHTML(p.name)} · PID ${p.pid}">${escapeHTML(p.name)}</span><span class="val cyan">${p.cpu}%</span><span class="val muted">${p.mem}%</span></div>`).join(''):'<div class="empty">暂无进程数据</div>';
 const now=Date.now();if(s.time!==lastSampleStamp){lastSampleStamp=s.time;lastSampleSeenAt=now;sampleBaseAge=Math.max(0,serverTime-s.time);}
 lastData=payload;document.body.dataset.sampleTime=String(s.time);drawCharts(payload);
}
async function poll(){
 const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),5500);
 try{const res=await fetch('/metrics',{cache:'no-store',signal:controller.signal});if(!res.ok)throw new Error(res.status);const payload=await res.json();render(payload);lastOkAt=Date.now();fetchFailed=false;}catch(e){fetchFailed=true;}finally{clearTimeout(timeout);updateStatus();setTimeout(poll,2000);}
}
let resizeFrame;addEventListener('resize',()=>{cancelAnimationFrame(resizeFrame);resizeFrame=requestAnimationFrame(()=>{if(lastData)render(lastData);});});
updateStatus();setInterval(updateStatus,1000);poll();
</script>
</body>
</html>
"""#.utf8)
}
