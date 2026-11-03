import Foundation

/// 监控大屏页面：一个自包含的 HTML 文件（无外部依赖），由 DashboardServer 直接下发。
/// 每 2 秒拉一次 /metrics；断网时保留最后读数并持续重试。
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
:root{color-scheme:dark;--bg:#0b1018;--card:#131c28;--inset:#0d1520;--border:#263447;--text:#eaf1fa;--muted:#a0afc1;--cyan:#58c8fa;--purple:#b49aff;--green:#61da95;--amber:#ffc369;--red:#ff8188;--orange:#ffb080;--font:14px;--number:38px;--pad:14px;--gap:10px}
*{box-sizing:border-box}html,body{margin:0;min-height:100%;width:100%}body{height:100vh;padding:12px;display:grid;grid-template-rows:auto minmax(0,1fr) auto;grid-gap:10px;background:var(--bg);color:var(--text);font:var(--font)/1.35 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;font-variant-numeric:tabular-nums;overflow:auto}
header{display:grid;grid-template-columns:14px minmax(0,1fr) auto;grid-gap:12px;align-items:center;padding:12px 16px;border-bottom:1px solid var(--border)}.host{font-size:21px;font-weight:700;overflow-wrap:anywhere}.ip,.uptime{color:var(--muted);font-size:var(--font)}.clock{font-size:29px;font-weight:700;line-height:1.2;text-align:right}.uptime{text-align:right;margin-top:4px}.connection{color:var(--green);margin-top:3px;font-size:var(--font);overflow-wrap:anywhere}.connection.warn{color:var(--amber)}.connection.off{color:var(--red)}.dot{width:11px;height:11px;border-radius:50%;background:var(--green);box-shadow:0 0 10px #61da9540}.dot.warn{background:var(--amber)}.dot.off{background:var(--red);box-shadow:0 0 10px #ff818840}
.grid{min-width:0;min-height:0;display:grid;grid-gap:var(--gap);grid-template-columns:repeat(2,minmax(0,1fr));grid-template-areas:"cpu mem" "network network" "system processes";grid-template-rows:minmax(180px,1fr) minmax(150px,.8fr) minmax(260px,1.3fr)}
.card{min-width:0;min-height:0;padding:var(--pad);border:1px solid var(--border);border-radius:12px;background:var(--card);display:flex;flex-direction:column}.cpu-card{grid-area:cpu}.memory-card{grid-area:mem}.network-card{grid-area:network}.system-card{grid-area:system}.process-card{grid-area:processes}
h2{margin:0 0 8px;font-size:var(--font);line-height:1.3;font-weight:650;letter-spacing:.04em;display:grid;grid-template-columns:auto minmax(0,1fr);grid-gap:8px;align-items:baseline}.hint{font-size:12px;color:var(--muted);font-weight:400;letter-spacing:0;text-align:right}.row{display:flex;flex-wrap:wrap;align-items:baseline}.big{font-size:var(--number);font-weight:700;line-height:1.1;letter-spacing:-.025em;white-space:nowrap}.sub{color:var(--muted);font-size:var(--font);overflow-wrap:anywhere}.value-sub{margin-left:10px}.cores{display:grid;grid-template-columns:repeat(8,minmax(0,1fr));grid-gap:4px;margin:9px 0 6px}.core{height:8px;border-radius:2px;background:#28374a}.core i{display:block;height:100%;border-radius:2px}.chart{position:relative;min-height:24px;flex:1;margin-top:7px}.chart canvas{position:absolute;top:0;left:0}.spark{display:block;width:100%;height:100%;min-height:24px}.chart-range{display:flex;justify-content:space-between;color:var(--muted);font-size:12px;margin-top:3px}.metric2{min-height:0;flex:1;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));grid-gap:20px}.network-metric{min-width:0;display:flex;flex-direction:column}.network-metric+.network-metric{border-left:1px solid var(--border);padding-left:20px}.rate{display:flex;flex-wrap:wrap;align-items:baseline;line-height:1.1;margin-top:3px}.rate-number{font-size:var(--number);font-weight:700;letter-spacing:-.025em}.unit{font-size:17px;font-weight:500;margin-left:5px;white-space:nowrap}.network-metric .chart{margin-top:8px}
.empty{color:var(--muted);align-self:center;grid-column:1/-1;padding:16px;text-align:center}.cyan{color:var(--cyan)}.orange{color:var(--orange)}.muted{color:var(--muted)}
.system-rows{display:grid;grid-template-rows:repeat(4,minmax(0,1fr));flex:1;min-height:0}.sysrow{display:grid;grid-template-columns:auto minmax(0,1fr);grid-gap:10px;align-content:center;padding:8px 0;border-bottom:1px solid var(--border)}.sysrow:last-child{border:0}.sysrow .value{text-align:right;overflow-wrap:anywhere}.table-head,.proc{display:grid;grid-template-columns:minmax(0,1fr) 70px 52px;grid-gap:5px;align-items:center}.table-head{color:var(--muted);font-size:12px;padding-bottom:5px;border-bottom:1px solid var(--border)}.table-head span:not(:first-child),.proc .val{text-align:right}.top{flex:1;min-height:0;display:grid;grid-auto-rows:minmax(27px,1fr)}.proc{padding:5px 0;border-bottom:1px solid #223044;font-size:var(--font)}.proc:last-child{border:0}.proc .name{min-width:0;overflow-wrap:anywhere;line-height:1.3}.proc .val{white-space:nowrap}.proc .name small{display:block;color:var(--muted);font-size:11px}footer{display:flex;justify-content:space-between;flex-wrap:wrap;font-size:12px;color:var(--muted);line-height:1.4;padding:0 3px}
@media(min-width:1000px) and (max-aspect-ratio:1/1){:root{--font:20px;--number:56px;--pad:22px;--gap:16px}body{padding:20px;grid-gap:16px}header{padding:18px 22px}.host{font-size:30px}.clock{font-size:42px}.hint,.chart-range,.table-head,footer{font-size:16px}h2{margin-bottom:12px}.grid{grid-template-rows:minmax(240px,1fr) minmax(210px,.85fr) minmax(355px,1.3fr)}.cores{grid-gap:6px;margin:13px 0 9px}.core{height:12px}.unit{font-size:20px}.table-head,.proc{grid-template-columns:minmax(0,1fr) 92px 74px}.proc{padding:8px 0}.proc .name small{font-size:14px}}
@media(min-aspect-ratio:4/3){.grid{grid-template-columns:repeat(3,minmax(0,1fr));grid-template-areas:"cpu mem network" "system processes processes";grid-template-rows:minmax(170px,1fr) minmax(225px,1.2fr)}.network-metric+.network-metric{padding-left:10px}.metric2{grid-gap:10px}.rate-number{font-size:32px}.unit{font-size:14px}}
@media(max-width:540px){body{height:auto;min-height:100vh}.grid{grid-template-columns:1fr;grid-template-areas:"cpu" "mem" "network" "system" "processes";grid-template-rows:200px 200px 190px 250px 300px}header{grid-template-columns:10px minmax(0,1fr);padding:8px}.clock-block{grid-column:2;text-align:left}.clock,.uptime{text-align:left}.host{font-size:19px}.table-head,.proc{grid-template-columns:minmax(0,1fr) 65px 60px}}
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
function rates(values,times,interval){return values.slice(1).map((v,i)=>{const dt=times&&times.length===values.length?times[i+1]-times[i]:interval;return dt>0?Math.max(0,v-values[i])/dt:0;});}
function rateValue(id,value){const parts=byteParts(value);$(id).innerHTML=`<span class="rate-number">${parts[0]}</span><span class="unit">${parts[1]}/s</span>`;}
function drawCharts(payload){
 const h=payload.history;
 spark($('cpuSpark'),h.cpu,'#58c8fa',{max:100});spark($('memSpark'),h.mem,'#b49aff',{max:100});
 const down=rates(h.netDown,h.time,payload.sampleInterval||2),up=rates(h.netUp,h.time,payload.sampleInterval||2),peak=Math.max(...down,...up,1024);
 spark($('netDownSpark'),down,'#58c8fa',{max:peak});spark($('netUpSpark'),up,'#ffb080',{max:peak});
 $('netScale').textContent='峰值 '+fmtBytes(peak)+'/s';
 if(down.length)rateValue('netDown',down[down.length-1]);if(up.length)rateValue('netUp',up[up.length-1]);
}
function render(payload){
 const s=payload.system;
 if(!s||!Number.isFinite(s.time)||!Array.isArray(s.cpuPercpu)||!Array.isArray(s.processes)||!payload.history)throw new Error('Incomplete metrics');
 const serverTime=Number.isFinite(payload.serverTime)?payload.serverTime:s.time;
 $('host').textContent=s.hostname||'Mac';$('ip').textContent=location.hostname+' · 采样 '+new Date(s.time*1000).toLocaleTimeString('zh-CN',{hour12:false});$('uptime').textContent='已运行 '+fmtUptime(s.uptimeSec);
 $('cpu').textContent=s.cpu.toFixed(0)+'%';$('loadavg').textContent='负载 '+s.load.join(' / ');
 if($('cores').children.length!==s.cpuPercpu.length)$('cores').innerHTML=s.cpuPercpu.map(()=>'<div class="core"><i></i></div>').join('');
 s.cpuPercpu.forEach((v,i)=>{const el=$('cores').children[i];el.title=`核心${i+1}：${v}%`;el.setAttribute('aria-label',el.title);el.firstChild.style.width=Math.min(v,100)+'%';el.firstChild.style.background=v<50?'var(--cyan)':v<85?'var(--amber)':'var(--red)';});
 $('mem').textContent=s.memUsedGB.toFixed(1)+' GB';$('memPct').textContent=s.memPercent.toFixed(0)+'% / '+s.memTotalGB+' GB';$('swap').textContent='交换 '+s.swapPercent+'%';
 $('disk').textContent=`${s.diskUsedGB} / ${s.diskTotalGB} GB（${s.diskPercent}%）`;$('load2').textContent=s.load.join(' / ');$('battery').textContent=s.batteryPercent!=null?s.batteryPercent+'%':'—（台式机）';$('procs').textContent=s.processes.length?'CPU前'+s.processes.length+'项见进程表':'暂无进程数据';
 $('top').innerHTML=s.processes.length?s.processes.map(p=>`<div class="proc"><span class="name" title="${escapeHTML(p.name)} · PID ${escapeHTML(p.pid)}">${escapeHTML(p.name)}</span><span class="val cyan">${escapeHTML(p.cpu)}%</span><span class="val muted">${escapeHTML(p.mem)}%</span></div>`).join(''):'<div class="empty">暂无进程数据</div>';
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
