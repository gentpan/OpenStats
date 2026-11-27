import Foundation

/// 监控大屏页面：一个自包含的 HTML 文件（无外部依赖），由 DashboardServer 直接下发。
/// 每 2 秒拉一次 /metrics；断网时保留最后读数并持续重试。
///
/// 内容、配色和卡片样式跟主窗口的仪表盘（OverviewPage）一致：健康分与机型标签、CPU / GPU / 内存、
/// 磁盘 / 网络 / 风扇、各核心占用、电池、高占用进程；颜色取自 DS.Palette 的浅色与深色两套。
/// 文字由 DashboardController 按应用的语言与单位设置排好，这里只管摆放、画图和动效。
///
/// 动效全部由真实读数驱动：扇叶按每台风扇的实际转速转（每 1000 RPM 每秒一圈，封顶每秒 4 圈），
/// 走势图在两次采样之间匀速向左滚动，数字、核心柱、进度条和电池环平滑过渡，进程换位时滑到新位置。
/// 系统开了“减弱动态效果”时这些都停掉，只换数值。页面不在前台时不画。
///
/// 字号随屏幕大小整体缩放，布局有三种：宽屏四列（进程表在右）、三列、手机两列。
/// 配色有深色、亮色和跟随系统三档：页脚的按钮切换并记在看大屏的那台设备上，
/// 网址带 `?theme=dark|light|auto` 时以网址为准（给没法点按钮的挂墙屏用）。
/// 大屏常放在旧平板、电视浏览器上，样式和脚本避开较新的写法（flex gap、color-mix、?. 等）
enum DashboardPage {
    static let html = Data(#"""
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OpenStats</title>
<style>
:root{color-scheme:dark;--bg:#0b0b0d;--surface:#17181b;--track:rgba(255,255,255,.10);--border:rgba(255,255,255,.07);--text:#f3f4f6;--text2:#9ca3af;--text3:#6b7280;--data:#3b82f6;--teal:#2dd4bf;--idle:#3f434a;--success:#22c55e;--warning:#f59e0b;--error:#f87171;--upload:#22c55e;--download:#3b82f6;--success-bg:rgba(34,197,94,.12);--warning-bg:rgba(245,158,11,.12);--error-bg:rgba(248,113,113,.12);--primary-bg:rgba(59,130,246,.12)}
:root[data-theme=light]{color-scheme:light;--bg:#ffffff;--surface:#f3f4f6;--track:rgba(0,0,0,.06);--border:rgba(0,0,0,.05);--text:#111827;--text2:#6b7280;--text3:#9ca3af;--data:#2563eb;--teal:#0d9488;--idle:#d1d5db;--success:#16a34a;--warning:#d97706;--error:#dc2626;--upload:#16a34a;--download:#2563eb;--success-bg:rgba(22,163,74,.12);--warning-bg:rgba(217,119,6,.12);--error-bg:rgba(220,38,38,.12);--primary-bg:rgba(37,99,235,.12)}
html{font-size:16px}
@media(min-width:641px){html{font-size:14px;font-size:clamp(13px,min(1.15vw,2.1vh),36px)}}
*{box-sizing:border-box}
html,body{margin:0;width:100%;min-height:100%}
body{height:100vh;padding:1.25rem;display:grid;grid-template-rows:auto minmax(0,1fr) auto;grid-gap:.875rem;background:var(--bg);color:var(--text);font:.875rem/1.3 -apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Helvetica Neue",sans-serif;font-variant-numeric:tabular-nums;-webkit-font-smoothing:antialiased;overflow:auto;transition:background-color .3s,color .3s}
header{display:grid;grid-template-columns:minmax(0,1fr) auto;grid-gap:.625rem 1rem;align-items:center;padding:0 .25rem}
.health{display:flex;align-items:center;min-width:0}
.health svg{width:1.75rem;height:1.75rem;flex:none;margin-right:.75rem;transition:color .4s}
.score{font-size:2.25rem;font-weight:600;line-height:1;letter-spacing:-.02em;margin-right:.875rem}
.summary{font-size:1rem;font-weight:500;color:var(--text2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.time{display:flex;align-items:baseline;justify-content:flex-end;white-space:nowrap}
.date{font-size:.875rem;color:var(--text2);margin-right:.75rem}
.clock{font-size:2.25rem;font-weight:600;line-height:1;letter-spacing:-.02em}
.chips{display:flex;flex-wrap:wrap;margin:-.375rem 0 0 -.5rem;min-width:0}
.chips .chip{margin:.375rem 0 0 .5rem}
.chip{display:inline-flex;align-items:center;white-space:nowrap;font-size:.75rem;font-weight:500;line-height:1.4;color:var(--text2);background:var(--track);border-radius:.3rem;padding:.125rem .5rem;transition:color .4s,background-color .4s}
.chip svg{width:1.15em;height:.75em;margin-right:.4em;flex:none}
.tone-primary{color:var(--data)}.tone-success{color:var(--success)}.tone-warning{color:var(--warning)}.tone-error{color:var(--error)}
.chip.tone-primary{background:var(--primary-bg)}.chip.tone-success{background:var(--success-bg)}.chip.tone-warning{background:var(--warning-bg)}.chip.tone-error{background:var(--error-bg)}
.status{display:flex;align-items:center;justify-content:flex-end;font-size:.75rem;font-weight:500;color:var(--text2);white-space:nowrap}
.live{width:.5rem;height:.5rem;border-radius:50%;background:var(--success);margin-right:.4rem;position:relative}
.live:after{content:"";position:absolute;top:0;left:0;width:100%;height:100%;border-radius:50%;background:inherit;animation:ping 2s ease-out infinite}
.status.warn .live{background:var(--warning)}.status.off .live{background:var(--error)}.status.warn .live:after,.status.off .live:after{animation:none}
.status.warn{color:var(--warning)}.status.off{color:var(--error)}
@keyframes ping{0%{transform:scale(1);opacity:.7}70%,100%{transform:scale(2.6);opacity:0}}
.grid{min-width:0;min-height:0;display:grid;grid-gap:.875rem;grid-template-columns:repeat(3,minmax(0,1fr));grid-template-rows:minmax(9rem,1fr) minmax(9rem,1fr) minmax(9rem,1fr) minmax(11rem,1.5fr);grid-template-areas:"cpu gpu mem" "disk net fan" "cores cores bat" "proc proc proc"}
.grid.no-battery{grid-template-areas:"cpu gpu mem" "disk net fan" "cores cores cores" "proc proc proc"}
.card{min-width:0;min-height:0;display:flex;flex-direction:column;padding:1rem;border-radius:.875rem;background:var(--surface);box-shadow:inset 0 0 0 1px var(--border);overflow:hidden;transition:background-color .3s}
.head{display:flex;align-items:center;min-height:1.5rem;font-size:.8125rem;font-weight:500;color:var(--text2)}
.head>svg{width:1rem;height:1rem;flex:none;margin-right:.4rem;fill:none;stroke:currentColor;stroke-width:1.5;stroke-linecap:round;stroke-linejoin:round}
.head .title{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.value{display:flex;align-items:baseline;margin-top:.5rem;white-space:nowrap}
.num{font-size:1.875rem;font-weight:600;line-height:1.1;letter-spacing:-.02em}
.unit{font-size:.8125rem;font-weight:500;color:var(--text2);margin-left:.2rem}
.chart{position:relative;flex:1;min-height:2.25rem;margin-top:.625rem}
.chart canvas{position:absolute;top:0;left:0;width:100%;height:100%}
.foot{margin-top:.625rem;font-size:.75rem;color:var(--text2);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;min-height:1.3em}
.foot b{font-weight:500}.up{color:var(--upload)}.down{color:var(--download)}
.progress{position:absolute;left:0;right:0;top:50%;height:.75rem;margin-top:-.375rem;border-radius:.25rem;background:var(--track);overflow:hidden}
.progress i{display:block;height:100%;border-radius:.25rem;background:var(--data);transition:width .8s cubic-bezier(.2,.7,.2,1),background-color .4s}
.fans{flex:1;min-height:2.75rem;display:flex;align-items:center;margin-top:.5rem}
.fanitem{flex:1;min-width:0;display:flex;align-items:center;margin-left:1rem}.fanitem:first-child{margin-left:0}
.fanitem svg{width:2.75rem;height:2.75rem;flex:none;color:var(--data)}
.fanitem .ring{fill:none;stroke:var(--track);stroke-width:1.5}
.fanitem .blades{fill:currentColor;transform-origin:20px 20px;will-change:transform}
.fanitem .hub{fill:var(--surface);stroke:currentColor;stroke-width:1.5}
.fanitem .meta{flex:1;min-width:0;margin-left:.625rem}
.fanitem .rpm{font-size:.9375rem;font-weight:600;white-space:nowrap}
.fanitem .rpm small{font-size:.6875rem;font-weight:500;color:var(--text2);margin-left:.2rem}
.fanitem .level{height:.25rem;border-radius:.125rem;background:var(--track);margin-top:.35rem;overflow:hidden}
.fanitem .level i{display:block;height:100%;border-radius:.125rem;background:var(--data);transition:width .8s cubic-bezier(.2,.7,.2,1)}
.legend{display:inline-flex;align-items:center;margin-left:.875rem;white-space:nowrap}
.legend i{width:.5rem;height:.5rem;border-radius:2px;margin-right:.35rem}
.legend b{font-weight:500;color:var(--text);margin-left:.35rem}
.corebars{flex:1;min-height:2.75rem;display:flex;margin-top:.625rem}
.cluster{display:flex;flex-direction:column;min-width:0;margin-left:.875rem}.cluster:first-child{margin-left:0}
.bars{flex:1;display:flex;min-height:0}
.bar{flex:1;position:relative;margin-left:.2rem;border-radius:.2rem;background:var(--track);overflow:hidden}.bar:first-child{margin-left:0}
.bar i{position:absolute;left:0;right:0;bottom:0;height:0;border-radius:.2rem;background:var(--data);transition:height .7s cubic-bezier(.2,.7,.2,1),background-color .4s}.bar.warn i{background:var(--warning)}
.cluster span{margin-top:.35rem;font-size:.75rem;color:var(--text3);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.battery{flex:1;display:flex;align-items:center;min-height:0;margin-top:.5rem}
.battery .info{flex:1;min-width:0}
.battery .state{font-size:.8125rem;font-weight:500;color:var(--text2);margin-top:.2rem}
.battery .watts{font-size:.8125rem;font-weight:500;color:var(--warning);margin-top:.15rem}
.gauge{width:4rem;height:4rem;flex:none;transform:rotate(-90deg)}
.gauge circle{fill:none;stroke-width:4}.gauge .t{stroke:var(--track)}.gauge .f{stroke:var(--success);stroke-linecap:round;transition:stroke-dasharray .8s cubic-bezier(.2,.7,.2,1),stroke .4s}
.gauge.tone-primary .f{stroke:var(--data)}.gauge.tone-error .f{stroke:var(--error)}
.tertiary{color:var(--text3)}
.cols{display:flex}.cols span,.proc span{width:5.5rem;text-align:right;flex:none}
.rows{flex:1;min-height:0;position:relative;margin-top:.375rem;overflow:hidden}
.proc{position:absolute;left:0;right:0;top:0;display:flex;align-items:center;font-size:.9375rem;border-top:1px solid var(--border);transition:transform .6s cubic-bezier(.2,.7,.2,1),opacity .4s;will-change:transform}
.proc.enter,.proc.leave{opacity:0}
.proc .name{flex:1;min-width:0;width:auto;text-align:left;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.proc .cpu{font-weight:500;transition:color .4s}.proc .mem{color:var(--text2)}.proc .cpu.tone-neutral{color:var(--text2)}
footer{display:flex;justify-content:space-between;align-items:center;font-size:.75rem;color:var(--text3);padding:0 .25rem}
.theme{font:inherit;font-weight:500;color:var(--text2);background:var(--track);border:0;border-radius:.3rem;padding:.125rem .6rem;cursor:pointer}
[hidden]{display:none!important}
@media(min-width:1100px) and (min-aspect-ratio:16/10){.grid{grid-template-columns:repeat(3,minmax(0,1fr)) minmax(0,1.3fr);grid-template-rows:repeat(3,minmax(9rem,1fr));grid-template-areas:"cpu gpu mem proc" "disk net fan proc" "cores cores bat proc"}.grid.no-battery{grid-template-areas:"cpu gpu mem proc" "disk net fan proc" "cores cores cores proc"}}
@media(max-width:640px){body{height:auto;min-height:100vh;padding:.875rem}header{grid-template-columns:minmax(0,1fr)}.time,.status{justify-content:flex-start}.time{grid-row:1}.clock{font-size:1.75rem}.score{font-size:2rem}.grid{grid-template-columns:repeat(2,minmax(0,1fr));grid-template-rows:none;grid-auto-rows:auto;grid-template-areas:"cpu gpu" "mem disk" "net net" "fan fan" "cores cores" "bat bat" "proc proc"}.grid.no-battery{grid-template-areas:"cpu gpu" "mem disk" "net net" "fan fan" "cores cores" "proc proc"}.card{padding:.875rem}.chart{flex:none;height:3rem}.fans{flex:none;height:3.25rem}.corebars{flex:none;height:5rem}.cols span,.proc span{width:4.5rem}}
@media(prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
</style>
<script>
(function(){var t=new URLSearchParams(location.search).get('theme');if(!/^(dark|light|auto)$/.test(t||'')){try{t=localStorage.getItem('theme')}catch(e){}}if(!/^(dark|light|auto)$/.test(t||''))t='dark';window.themeChoice=t;document.documentElement.setAttribute('data-theme',t==='auto'?(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark'):t);})();
</script>
</head>
<body>
<header>
 <div class="health"><svg id="healthIcon" viewBox="0 0 24 24" aria-hidden="true"></svg><span class="score" id="score">--</span><span class="summary" id="summary" role="status"></span></div>
 <div class="time"><span class="date" id="date"></span><span class="clock" id="clock">--:--:--</span></div>
 <div class="chips" id="chips"></div>
 <div class="status warn" id="status" role="status"><i class="live"></i><span id="statusText"></span></div>
</header>
<main class="grid no-battery" id="dashboard">
 <section class="card" style="grid-area:cpu"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><rect x="4" y="4" width="8" height="8" rx="1.5"/><path d="M6.5 1.5v2.5M9.5 1.5v2.5M6.5 12v2.5M9.5 12v2.5M1.5 6.5H4M1.5 9.5H4M12 6.5h2.5M12 9.5h2.5"/></svg><span class="title">CPU</span><span class="chip" id="cpuChip" hidden></span></div><div class="value"><span class="num" id="cpu">—</span><span class="unit">%</span></div><div class="chart"><canvas id="cpuChart" role="img" aria-label="CPU"></canvas></div><div class="foot" id="cpuFoot"></div></section>
 <section class="card" style="grid-area:gpu"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="8.5" rx="1.5"/><path d="M8 11v2.5M5.5 13.5h5"/></svg><span class="title">GPU</span><span class="chip" id="gpuChip" hidden></span></div><div class="value"><span class="num" id="gpu">—</span><span class="unit">%</span></div><div class="chart"><canvas id="gpuChart" role="img" aria-label="GPU"></canvas></div><div class="foot" id="gpuFoot"></div></section>
 <section class="card" style="grid-area:mem"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="4.5" width="13" height="6" rx="1"/><path d="M4 10.5v2M6.7 10.5v2M9.3 10.5v2M12 10.5v2M5 7.5h1.5M9.5 7.5H11"/></svg><span class="title" data-label="memory">内存</span><span class="chip" id="memChip" hidden></span></div><div class="value"><span class="num" id="mem">—</span><span class="unit">%</span></div><div class="chart"><canvas id="memChart" role="img" aria-label="内存"></canvas></div><div class="foot" id="memFoot"></div></section>
 <section class="card" style="grid-area:disk"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><rect x="2" y="2.5" width="12" height="11" rx="2"/><path d="M2 9.5h12"/><circle cx="11.2" cy="11.6" r=".4"/></svg><span class="title" data-label="disk">磁盘</span><span class="chip" id="diskChip" hidden></span></div><div class="value"><span class="num" id="disk">—</span><span class="unit">%</span></div><div class="chart"><div class="progress"><i id="diskBar" style="width:0"></i></div></div><div class="foot" id="diskFoot"></div></section>
 <section class="card" style="grid-area:net"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6"/><ellipse cx="8" cy="8" rx="2.6" ry="6"/><path d="M2 8h12"/></svg><span class="title" data-label="network">网络</span><span class="chip" id="netChip" hidden></span></div><div class="value"><span class="num" id="net">—</span><span class="unit" id="netUnit"></span></div><div class="chart"><canvas id="netChart" role="img" aria-label="网络"></canvas></div><div class="foot"><b class="up">↑</b> <b id="netUp">—</b>&nbsp;&nbsp;&nbsp;<b class="down">↓</b> <b id="netDown">—</b></div></section>
 <section class="card" style="grid-area:fan"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.2"/><circle cx="8" cy="8" r="1.2"/><path d="M8 6.8C7 4.5 8 2.6 9.6 2.3M9.2 8c2.3-1 4.2 0 4.5 1.6M8 9.2c1 2.3 0 4.2-1.6 4.5M6.8 8c-2.3 1-4.2 0-4.5-1.6"/></svg><span class="title" data-label="fan">风扇</span><span class="chip" id="fanChip" hidden></span></div><div class="value"><span class="num" id="fan">—</span><span class="unit">RPM</span></div><div class="fans" id="fans"></div></section>
 <section class="card" style="grid-area:cores"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M3 13V8M6.3 13V4M9.7 13V6.5M13 13V2.5"/></svg><span class="title" data-label="cores">各核心占用</span><span class="legend"><i style="background:var(--data)"></i><span data-label="user">用户</span><b id="cpuUser">—</b></span><span class="legend"><i style="background:var(--teal)"></i><span data-label="system">系统</span><b id="cpuSystem">—</b></span></div><div class="corebars" id="cores"></div></section>
 <section class="card" style="grid-area:bat" id="batteryCard" hidden><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.5" y="4.5" width="11.5" height="7" rx="2"/><path d="M14.8 7v2"/></svg><span class="title" data-label="battery">电池</span><span class="chip" id="batChip" hidden></span></div><div class="battery"><div class="info"><div class="num" id="bat">—</div><div class="state" id="batState"></div><div class="watts" id="batWatts" hidden></div></div><svg class="gauge" id="batRing" viewBox="0 0 36 36" aria-hidden="true"><circle class="t" cx="18" cy="18" r="15"></circle><circle class="f" id="batArc" cx="18" cy="18" r="15" stroke-dasharray="0 100"></circle></svg></div><div class="foot tertiary" id="batFoot"></div></section>
 <section class="card" style="grid-area:proc"><div class="head"><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2.5 4h11M2.5 8h8M2.5 12h5"/></svg><span class="title" data-label="processes">高占用进程</span><span class="cols"><span>CPU</span><span data-label="memory">内存</span></span></div><div class="rows" id="top"></div></section>
</main>
<footer><span id="host"></span><button class="theme" id="theme" type="button"></button></footer>
<script>
'use strict';
var $=function(id){return document.getElementById(id);};
var themeNames={dark:'深色',light:'亮色',auto:'跟随系统'},systemLight=matchMedia('(prefers-color-scheme: light)');
var still=matchMedia('(prefers-reduced-motion: reduce)').matches;
var palette={},lastData=null,lastOkAt=0,lastSampleStamp=null,lastSampleSeenAt=0,sampleBaseAge=0,fetchFailed=false,coreKey='';
var arrivedAt=0,settled=true,interval=2000,netPeak=0,tweens={},fanSpin=[],procRows={},lastFrame=0;
var icons={ok:'<path fill="currentColor" d="M12 2l2.4 1.8 3-.3 1.2 2.8 2.8 1.2-.3 3L23 12l-1.9 2.4.3 3-2.8 1.2-1.2 2.8-3-.3L12 23l-2.4-1.9-3 .3-1.2-2.8-2.8-1.2.3-3L1 12l1.9-2.4-.3-3 2.8-1.2 1.2-2.8 3 .3z"/><path fill="none" stroke="var(--bg)" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M7.8 12.3l2.9 2.9 5.5-6"/>',
 warn:'<path fill="currentColor" d="M12 2.5c.8 0 1.5.4 1.9 1.1l8.6 15c.8 1.4-.2 3.1-1.9 3.1H3.4c-1.7 0-2.7-1.7-1.9-3.1l8.6-15c.4-.7 1.1-1.1 1.9-1.1z"/><path fill="none" stroke="var(--bg)" stroke-width="2.2" stroke-linecap="round" d="M12 9v5.2M12 17.6v.2"/>'};
var pulse='<svg viewBox="0 0 22 14" aria-hidden="true"><polyline fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" points="1,7.5 5,7.5 9.2,1 11.2,13 15,4.2 17,7.5 21,7.5"/></svg>';
var blade='<path d="M20 18.2c-1.6-4.2-.4-9.6 3.4-12.4 1.5-1.1 3.4-.2 3.5 1.6.3 4.4-2.300 8.600-6.900 10.800z"/>';
var fanSVG='<svg viewBox="0 0 40 40" aria-hidden="true"><circle class="ring" cx="20" cy="20" r="18.5"/><g class="blades">'+[0,72,144,216,288].map(function(a){return '<g transform="rotate('+a+' 20 20)">'+blade+'</g>';}).join('')+'</g><circle class="hub" cx="20" cy="20" r="3.4"/></svg>';
function escapeHTML(value){return String(value).replace(/[&<>"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];});}
function text(id,value){var el=typeof id==='string'?$(id):id;if(el.textContent!==value)el.textContent=value;}
function chip(id,value,tone){var el=$(id);if(!value){el.hidden=true;return;}el.hidden=false;text(el,value);el.className='chip'+(tone&&tone!=='neutral'?' tone-'+tone:'');}
function rgba(hex,alpha){var n=parseInt(hex.replace('#',''),16);return 'rgba('+(n>>16&255)+','+(n>>8&255)+','+(n&255)+','+alpha+')';}
// 数字不直接跳到新值，而是在大约半秒里滚过去
function tween(id,target,format){
 var t=tweens[id];if(!t)t=tweens[id]={el:$(id),value:null};
 t.target=target;t.format=format||function(v){return v.toFixed(0);};
 if(target===null){t.value=null;text(t.el,'—');return;}
 if(t.value===null||still){t.value=target;text(t.el,t.format(target));}
}
function stepTweens(dt){
 for(var id in tweens){var t=tweens[id];if(t.target===null||t.value===null||t.value===t.target)continue;
  var diff=t.target-t.value;t.value=Math.abs(diff)<Math.max(.4,Math.abs(t.target)*.002)?t.target:t.value+diff*Math.min(1,dt*6);text(t.el,t.format(t.value));}
}
function applyTheme(){
 document.documentElement.setAttribute('data-theme',themeChoice==='auto'?(systemLight.matches?'light':'dark'):themeChoice);
 text('theme',themeNames[themeChoice]);
 var style=getComputedStyle(document.documentElement);palette={};
 ['data','teal','idle','warning','track','upload','download','surface'].forEach(function(k){palette[k]=style.getPropertyValue('--'+k).trim();});
 drawCharts(1);
}
function updateStatus(){
 var now=Date.now(),date=new Date(now);
 text('clock',date.toLocaleTimeString([], {hour12:false}));text('date',date.toLocaleDateString([], {month:'long',day:'numeric',weekday:'short'}));
 var age=lastSampleSeenAt?Math.max(0,sampleBaseAge+(now-lastSampleSeenAt)/1000):null;
 var disconnected=fetchFailed||(lastOkAt&&now-lastOkAt>6500),stale=age!==null&&age>8;
 var message=location.host,state='live';
 if(!lastOkAt){message=fetchFailed?'连接失败 · 正在重试…':'连接中…';state=fetchFailed?'offline':'waiting';}
 else if(disconnected){message='连接中断 · 保留上次读数';state='offline';}
 else if(stale){message='采样已过期 · 保留上次读数';state='stale';}
 text('statusText',message);$('status').className='status'+(state==='offline'?' off':state==='live'?'':' warn');
 document.body.setAttribute('data-connection',state);document.body.setAttribute('data-sample-age',age===null?'':age.toFixed(1));
}
function prepare(canvas){
 var dpr=window.devicePixelRatio||1,w=canvas.clientWidth,h=canvas.clientHeight;if(!w||!h)return null;
 var pw=Math.round(w*dpr),ph=Math.round(h*dpr);if(canvas.width!==pw||canvas.height!==ph){canvas.width=pw;canvas.height=ph;}
 var ctx=canvas.getContext('2d');if(!ctx)return null;ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,w,h);
 return{ctx:ctx,w:w,h:h,u:parseFloat(getComputedStyle(document.documentElement).fontSize)/16};
}
function roundBar(ctx,x,y,w,h,r){r=Math.min(r,w/2,h/2);ctx.beginPath();ctx.moveTo(x,y+h);ctx.lineTo(x,y+r);ctx.arcTo(x,y,x+r,y,r);ctx.lineTo(x+w-r,y);ctx.arcTo(x+w,y,x+w,y+r,r);ctx.lineTo(x+w,y+h);ctx.closePath();}
// 柱状历史：一次采样一根柱子，屏幕越宽能看到的时间越长；phase 从 0 到 1 时整排向左挪一格，新柱子从右边进来
function bars(canvas,values,phase){
 var p=prepare(canvas);if(!p)return;var ctx=p.ctx,bw=Math.max(2,3.5*p.u),gap=Math.max(1,2*p.u),pitch=bw+gap,base=Math.max(2,2*p.u);
 var capacity=Math.min(150,Math.floor((p.w+gap)/pitch)),shift=(1-phase)*pitch,start=p.w-capacity*pitch+gap;
 for(var i=-1;i<capacity;i++){
  var index=values.length-capacity+i,x=start+i*pitch+shift;if(x>p.w)continue;
  if(index<0||index>=values.length){ctx.fillStyle=palette.track;ctx.fillRect(x,p.h-base,bw,base);continue;}
  var v=Math.min(1,Math.max(0,values[index]/100)),bh=Math.max(base,p.h*v);
  ctx.fillStyle=v<.02?palette.idle:v>=.8?palette.warning:palette.data;roundBar(ctx,x,p.h-bh,bw,bh,1.5*p.u);ctx.fill();
 }
}
// 折线走势：最新的点在右边缘，phase 从 0 到 1 时整条线向左滚一格；末端有一个跟着数值上下移动的圆点
function lines(canvas,series,capacity,max,phase){
 var p=prepare(canvas);if(!p)return;var ctx=p.ctx,line=1.6*p.u,dot=3*p.u,right=p.w-dot-line,top=dot+line,usable=p.h-top-line,step=right/Math.max(1,capacity-1),shift=(1-phase)*step;
 series.forEach(function(s){
  var values=s.values.slice(-(capacity+1));if(values.length<2)return;
  var x=function(i){return right-(values.length-1-i)*step+shift;},y=function(v){return top+usable*(1-Math.min(1,Math.max(0,v/max)));};
  var last=values.length-1,edgeY=y(values[last-1])+(y(values[last])-y(values[last-1]))*phase;
  ctx.save();ctx.beginPath();ctx.rect(0,0,right,p.h);ctx.clip();
  ctx.beginPath();ctx.moveTo(x(0),y(values[0]));
  for(var i=1;i<values.length;i++){var mx=(x(i-1)+x(i))/2;ctx.bezierCurveTo(mx,y(values[i-1]),mx,y(values[i]),x(i),y(values[i]));}
  ctx.strokeStyle=s.color;ctx.lineWidth=line;ctx.lineJoin='round';ctx.lineCap='round';ctx.stroke();
  ctx.lineTo(x(last),p.h);ctx.lineTo(x(0),p.h);ctx.closePath();
  var fill=ctx.createLinearGradient(0,top,0,p.h);fill.addColorStop(0,rgba(s.color,s.fill));fill.addColorStop(1,rgba(s.color,0));ctx.fillStyle=fill;ctx.fill();ctx.restore();
  ctx.beginPath();ctx.arc(right,edgeY,dot,0,Math.PI*2);ctx.fillStyle=palette.surface;ctx.fill();
  ctx.beginPath();ctx.arc(right,edgeY,dot-line/2,0,Math.PI*2);ctx.fillStyle=s.color;ctx.fill();
 });
}
function rates(values,times,fallback){return values.slice(1).map(function(v,i){var dt=times&&times.length===values.length?times[i+1]-times[i]:fallback;return dt>0?Math.max(0,v-values[i])/dt:0;});}
function drawCharts(phase){
 if(!lastData)return;var h=lastData.history,n=150;
 bars($('cpuChart'),h.cpu,phase);
 lines($('gpuChart'),[{values:h.gpu||[],color:palette.teal,fill:.22}],n,100,phase);
 lines($('memChart'),[{values:h.mem,color:palette.data,fill:.22}],n,100,phase);
 var down=rates(h.netDown,h.time,lastData.sampleInterval||2),up=rates(h.netUp,h.time,lastData.sampleInterval||2);
 var peak=Math.max.apply(null,down.concat(up,[65536]))*1.15;netPeak=netPeak&&!still?netPeak+(peak-netPeak)*.12:peak;
 lines($('netChart'),[{values:down,color:palette.download,fill:.18},{values:up,color:palette.upload,fill:.18}],n-1,netPeak,phase);
}
function renderCores(s){
 var clusters=s.clusters&&s.clusters.length?s.clusters:[{name:'',cores:s.cpuPercpu.map(function(_,i){return i;})}];
 var key=clusters.map(function(c){return c.name+':'+c.cores.join(',');}).join('|'),root=$('cores');
 if(key!==coreKey){coreKey=key;root.innerHTML=clusters.map(function(c){return '<div class="cluster" style="flex:'+c.cores.length+'"><div class="bars">'+c.cores.map(function(i){return '<div class="bar" data-core="'+i+'"><i></i></div>';}).join('')+'</div><span>'+escapeHTML(c.name)+'</span></div>';}).join('');root.offsetHeight;}
 Array.prototype.forEach.call(root.querySelectorAll('.bar'),function(el){var v=Math.min(100,Math.max(0,s.cpuPercpu[+el.getAttribute('data-core')]||0));el.className='bar'+(v>=80?' warn':'');el.firstChild.style.height=v+'%';});
}
// 每台风扇一个扇叶，按它自己的真实转速转；数量变了才重建
function renderFans(fan){
 var list=fan&&fan.fans?fan.fans:[],root=$('fans');
 if(fanSpin.length!==list.length){root.innerHTML=list.map(function(_,i){return '<div class="fanitem">'+fanSVG+'<div class="meta"><div class="rpm"><span id="fanRpm'+i+'">—</span><small>RPM</small></div><div class="level"><i style="width:0"></i></div></div></div>';}).join('');
  fanSpin=list.map(function(_,i){delete tweens['fanRpm'+i];return{el:root.children[i].querySelector('.blades'),bar:root.children[i].querySelector('.level i'),angle:0,speed:0,target:0};});}
 list.forEach(function(f,i){fanSpin[i].target=Math.min(4,Math.max(0,f.rpm/1000));fanSpin[i].bar.style.width=Math.min(100,f.fraction*100)+'%';tween('fanRpm'+i,f.rpm,function(v){return Math.round(v).toLocaleString();});});
}
function stepFans(dt){
 if(still)return;
 fanSpin.forEach(function(f){f.speed+=(f.target-f.speed)*Math.min(1,dt*2);if(f.speed<.01)return;f.angle=(f.angle+f.speed*360*dt)%360;f.el.style.transform='rotate('+f.angle.toFixed(1)+'deg)';});
}
// 进程行按 PID 认行：还在榜上的滑到新名次，新上榜的淡入，掉出去的淡出
function renderProcesses(list){
 var root=$('top'),seen={},phone=innerWidth<=640,unit=parseFloat(getComputedStyle(document.documentElement).fontSize);
 var rowH=phone?2.25*unit:Math.max(1.7*unit,Math.min(3.2*unit,root.clientHeight/Math.max(1,list.length)));
 if(phone)root.style.height=rowH*list.length+'px';else root.style.height='';
 list.forEach(function(p,i){
  var key='p'+p.pid,row=procRows[key];seen[key]=true;
  if(!row){row=procRows[key]=document.createElement('div');row.className='proc enter';row.innerHTML='<span class="name"></span><span class="cpu"></span><span class="mem"></span>';row.style.transform='translateY('+i*rowH+'px)';root.appendChild(row);row.offsetHeight;}
  row.className='proc';row.style.height=rowH+'px';row.style.transform='translateY('+i*rowH+'px)';row.style.borderTopColor=i?'':'transparent';
  text(row.children[0],p.name);row.children[0].title='PID '+p.pid;text(row.children[1],p.cpuText||p.cpu+'%');row.children[1].className='cpu tone-'+(p.tone||'neutral');text(row.children[2],p.memText||p.mem+'%');
 });
 Object.keys(procRows).forEach(function(key){if(seen[key])return;var row=procRows[key];delete procRows[key];row.className='proc leave';setTimeout(function(){if(row.parentNode)row.parentNode.removeChild(row);},still?0:450);});
}
function render(payload){
 var s=payload.system;
 if(!s||!isFinite(s.time)||!Array.isArray(s.cpuPercpu)||!Array.isArray(s.processes)||!payload.history)throw new Error('Incomplete metrics');
 var serverTime=isFinite(payload.serverTime)?payload.serverTime:s.time,labels=s.labels||{};
 Array.prototype.forEach.call(document.querySelectorAll('[data-label]'),function(el){var value=labels[el.getAttribute('data-label')];if(value)text(el,value);});
 var health=s.health||{score:null,summary:'',tone:'success'};
 tween('score',health.score);text('summary',health.summary);
 var icon=health.tone==='success'?'ok':'warn';if($('healthIcon').getAttribute('data-icon')!==icon){$('healthIcon').innerHTML=icons[icon];$('healthIcon').setAttribute('data-icon',icon);}
 $('healthIcon').setAttribute('class','tone-'+health.tone);
 var chips=[s.hostname||'Mac'].concat(s.chips||[]),chipKey=chips.join('|');
 if($('chips').getAttribute('data-key')!==chipKey){$('chips').setAttribute('data-key',chipKey);$('chips').innerHTML=chips.map(function(c,i){return '<span class="chip">'+(i?'':pulse)+escapeHTML(c)+'</span>';}).join('');}
 text('host','OpenStats');document.title=(s.hostname||'Mac')+' · OpenStats';
 tween('cpu',s.cpu);chip('cpuChip',s.cpuTemp&&s.cpuTemp.text,s.cpuTemp&&s.cpuTemp.tone);text('cpuFoot',s.cpuFooter||'');
 text('cpuUser',s.cpuUser||'—');text('cpuSystem',s.cpuSystem||'—');renderCores(s);
 tween('gpu',s.gpu?s.gpu.percent:null);chip('gpuChip',s.gpuTemp&&s.gpuTemp.text,s.gpuTemp&&s.gpuTemp.tone);text('gpuFoot',s.gpu?s.gpu.footer:'');
 tween('mem',s.memPercent);chip('memChip',s.memPressure&&s.memPressure.text,s.memPressure&&s.memPressure.tone);text('memFoot',s.memText||'');
 tween('disk',s.diskPercent);chip('diskChip',s.diskCapacity);text('diskFoot',s.diskFooter||'');
 $('diskBar').style.width=Math.min(100,s.diskPercent)+'%';$('diskBar').style.background=s.diskPercent>90?'var(--warning)':'';
 var total=(s.netTotalText||'—').split(' ');text('net',total[0]);text('netUnit',total.slice(1).join(' '));
 chip('netChip',s.interface);text('netUp',s.netUpText||'—');text('netDown',s.netDownText||'—');
 tween('fan',s.fan&&isFinite(s.fan.rpmValue)?s.fan.rpmValue:null,function(v){return Math.round(v).toLocaleString();});chip('fanChip',s.fan&&s.fan.chip);renderFans(s.fan);
 var b=s.battery;$('batteryCard').hidden=!b;$('dashboard').className='grid'+(b?'':' no-battery');
 if(b){text('bat',b.percent);text('batState',b.state);$('batWatts').hidden=!b.watts;text('batWatts',b.watts?'⚡ '+b.watts:'');
  chip('batChip',b.health&&b.health.text,b.health&&b.health.tone);text('batFoot',b.detail||'');
  var arc=2*Math.PI*15;$('batArc').setAttribute('stroke-dasharray',(arc*Math.min(1,Math.max(0,b.level))).toFixed(1)+' '+arc.toFixed(1));$('batRing').setAttribute('class','gauge tone-'+b.tone);}
 renderProcesses(s.processes);
 var now=Date.now(),fresh=s.time!==lastSampleStamp;
 if(fresh){if(lastSampleStamp!==null)interval=Math.min(4000,Math.max(1000,(s.time-lastSampleStamp)*1000));lastSampleStamp=s.time;lastSampleSeenAt=now;sampleBaseAge=Math.max(0,serverTime-s.time);}
 var first=!lastData;lastData=payload;document.body.setAttribute('data-sample-time',String(s.time));
 if(first||still){arrivedAt=0;drawCharts(1);}else if(fresh){arrivedAt=performance.now();settled=false;}
}
function frame(now){
 requestAnimationFrame(frame);
 if(document.hidden||now-lastFrame<30)return;var dt=Math.min(.25,(now-lastFrame)/1000);lastFrame=now;
 stepTweens(dt);stepFans(dt);
 if(lastData&&!still){var phase=arrivedAt?Math.min(1,(now-arrivedAt)/interval):1;if(phase<1||!settled){drawCharts(phase);settled=phase>=1;}}
}
function poll(){
 var controller=typeof AbortController==='function'?new AbortController():null,timeout=setTimeout(function(){if(controller)controller.abort();},5500);
 fetch('/metrics',{cache:'no-store',signal:controller?controller.signal:undefined}).then(function(res){if(!res.ok)throw new Error(res.status);return res.json();})
  .then(function(payload){render(payload);lastOkAt=Date.now();fetchFailed=false;}).catch(function(){fetchFailed=true;})
  .then(function(){clearTimeout(timeout);updateStatus();setTimeout(poll,2000);});
}
var resizeFrame;addEventListener('resize',function(){cancelAnimationFrame(resizeFrame);resizeFrame=requestAnimationFrame(function(){if(lastData){renderProcesses(lastData.system.processes);drawCharts(1);}});});
$('theme').addEventListener('click',function(){var order=['dark','light','auto'];themeChoice=order[(order.indexOf(themeChoice)+1)%3];try{localStorage.setItem('theme',themeChoice);}catch(e){}applyTheme();});
if(systemLight.addEventListener)systemLight.addEventListener('change',function(){if(themeChoice==='auto')applyTheme();});else if(systemLight.addListener)systemLight.addListener(function(){if(themeChoice==='auto')applyTheme();});
applyTheme();updateStatus();setInterval(updateStatus,1000);poll();requestAnimationFrame(frame);
</script>
</body>
</html>
"""#.utf8)
}
