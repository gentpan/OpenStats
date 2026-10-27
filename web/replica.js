/* OpenStats 官网 · 应用界面还原
   菜单栏读数、合并面板（总览与各项详情）、桌面小组件和下面几块演示都是 HTML 重建，
   数据是本页随机游走生成的模拟值，不读取访客电脑的任何信息。
   版式、配色与字号对应应用里的 CombinedPopover、PopoverHero 与各详情弹窗。 */
(() => {
  "use strict";

  // ── 工具 ──────────────────────────────────────────────────
  const $ = (sel, root = document) => root.querySelector(sel);
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const walk = (v, step, lo, hi) => clamp(v + (Math.random() - 0.5) * step, lo, hi);
  const fill = (n, f) => Array.from({ length: n }, f);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const read = (key, fallback) => { try { return localStorage.getItem(key) || fallback; } catch { return fallback; } };
  const write = (key, value) => { try { localStorage.setItem(key, value); } catch { /* 隐私模式下不可用 */ } };
  function push(list, value, size) { list.push(value); if (list.length > size) list.shift(); }

  // ── 模拟数据 ──────────────────────────────────────────────
  const HISTORY = 300;
  const S = {
    cores: fill(18, (_, i) => (i < 6 ? 0.18 : 0.08) + Math.random() * 0.15),
    coreHistory: [],
    cpu: 0.16, cpuHistory: fill(HISTORY, () => 0.1 + Math.random() * 0.12),
    gpu: 0.2, gpuHistory: fill(60, () => 0.08 + Math.random() * 0.2),
    mem: 0.66, memHistory: fill(60, () => 0.66),
    down: 820 * 1024, up: 46 * 1024,
    downHistory: fill(60, () => Math.random() * 900 * 1024), upHistory: fill(60, () => Math.random() * 120 * 1024),
    probes: fill(60, () => 16 + Math.random() * 8),
    diskRead: 2 * 1024 * 1024, diskWrite: 6 * 1024 * 1024,
    readHistory: fill(60, () => Math.random() * 4e6), writeHistory: fill(60, () => Math.random() * 9e6),
    cpuTemp: 56, gpuTemp: 51, memTemp: 52, batteryTemp: 33, palmTemp: 31,
    fans: [1356, 1455], fanMode: "auto", fanHistory: fill(60, () => 0.25),
    power: 23, powerHistory: fill(60, () => 20 + Math.random() * 6),
    gpuPower: 0.4,
    keepAwake: false, awakeDur: 0, awakeEnd: null, awakeMode: "display",
    sharePerCore: false, cpuSpan: 60,
    style: read("os-style", "stacked"),
    cleaned: false, confirming: false,
  };
  const FAN_MAX = [5349, 5777];
  const BATTERY_DAY = fill(96, (_, i) => clamp(0.35 + i / 70, 0, 1)).map((v, i) => (i > 80 ? 1 : v));
  S.coreHistory = fill(36, () => S.cores.map((v) => walk(v, 0.2, 0, 1)));

  const APPS = [
    ["Safari", 1, 0.9, 2.1e9], ["Xcode", 1, 0.6, 3.4e9], ["WindowServer", 3, 0.35, 0.6e9], ["音乐", 4, 0.14, 0.4e9],
    ["照片", 5, 0.1, 1.1e9], ["终端", 3, 0.08, 0.2e9], ["邮件", 1, 0.05, 0.5e9], ["访达", 8, 0.04, 0.3e9], ["OpenStats", 1, 0.03, 0.04e9],
  ].map(([name, color, cpu, mem]) => ({ name, color, cpu, mem, procs: 1 + Math.floor(Math.random() * 12) }));
  const NET_APPS = [["Safari", 1], ["音乐", 4], ["邮件", 1], ["照片", 5], ["终端", 3]]
    .map(([name, color]) => ({ name, color, down: Math.random() * 400 * 1024, up: Math.random() * 40 * 1024 }));
  const DISK_APPS = [["照片", 5], ["Xcode", 1], ["Safari", 1], ["终端", 3], ["mds_stores", 8]]
    .map(([name, color]) => ({ name, color, read: Math.random() * 2e6, write: Math.random() * 3e6 }));

  function tick() {
    S.cores = S.cores.map((v, i) => walk(v, 0.16, 0.02, i < 6 ? 0.85 : 0.6));
    push(S.coreHistory, S.cores.slice(), 36);
    S.cpu = S.cores.reduce((a, b) => a + b, 0) / S.cores.length;
    push(S.cpuHistory, S.cpu, HISTORY);
    S.gpu = walk(S.gpu, 0.14, 0.02, 0.7); push(S.gpuHistory, S.gpu, 60);
    S.mem = walk(S.mem, 0.008, 0.6, 0.74); push(S.memHistory, S.mem, 60);
    S.down = clamp(S.down * (0.55 + Math.random() * 0.9) + Math.random() * 40000, 3000, 30 * 1024 * 1024);
    S.up = clamp(S.up * (0.55 + Math.random() * 0.9) + Math.random() * 6000, 600, 4 * 1024 * 1024);
    push(S.downHistory, S.down, 60); push(S.upHistory, S.up, 60);
    const roll = Math.random();
    push(S.probes, roll < 0.015 ? null : roll < 0.04 ? 120 + Math.random() * 80 : 16 + Math.random() * 8, 60);
    S.diskRead = clamp(S.diskRead * (0.4 + Math.random() * 1.2), 0, 60e6);
    S.diskWrite = clamp(S.diskWrite * (0.4 + Math.random() * 1.2) + Math.random() * 1e6, 0, 80e6);
    push(S.readHistory, S.diskRead, 60); push(S.writeHistory, S.diskWrite, 60);
    S.cpuTemp = walk(S.cpuTemp, 1.6, 44, 74); S.gpuTemp = walk(S.gpuTemp, 1.2, 42, 66); S.memTemp = walk(S.memTemp, 0.8, 44, 62);
    S.power = walk(S.power, 2, 12, 38); push(S.powerHistory, S.power, 60);
    S.gpuPower = clamp(S.gpu * 8 + Math.random() * 0.3, 0.1, 9);
    const target = { auto: 0.25 + S.cpu * 0.2, cool: 0.6, max: 1 }[S.fanMode];
    S.fans = S.fans.map((rpm, i) => Math.round(rpm + (FAN_MAX[i] * target - rpm) * 0.35));
    push(S.fanHistory, Math.max(S.fans[0] / FAN_MAX[0], S.fans[1] / FAN_MAX[1]), 60);
    APPS.forEach((a) => { a.cpu = clamp(a.cpu + (Math.random() - 0.5) * 0.25, 0.01, 2.5); a.mem = clamp(a.mem * (0.98 + Math.random() * 0.04), 2e7, 6e9); });
    // 乘上随机系数后再加一点基线，免得几轮之后都衰减到 0
    NET_APPS.forEach((a, i) => { a.down = clamp(a.down * (0.5 + Math.random() * 0.9) + (5 - i) * 6000 * Math.random(), 0, 9e6); a.up = clamp(a.up * (0.5 + Math.random() * 0.9) + (5 - i) * 900 * Math.random(), 0, 1e6); });
    DISK_APPS.forEach((a, i) => { a.read = clamp(a.read * (0.5 + Math.random() * 0.9) + (5 - i) * 40000 * Math.random(), 0, 9e6); a.write = clamp(a.write * (0.5 + Math.random() * 0.9) + (5 - i) * 60000 * Math.random(), 0, 9e6); });
    if (S.keepAwake && S.awakeEnd && Date.now() > S.awakeEnd) { S.keepAwake = false; S.awakeEnd = null; }
  }

  // ── 格式化 ────────────────────────────────────────────────
  const pctNum = (v) => Math.round(clamp(v, 0, 1) * 100);
  const pct = (v) => `${pctNum(v)}%`;
  function rate(bps) {
    const units = ["B/s", "KB/s", "MB/s", "GB/s"];
    let value = Math.max(0, bps), i = 0;
    while (value >= 999.5 && i < units.length - 1) { value /= 1024; i++; }
    return `${i >= 2 && value < 9.95 ? value.toFixed(1) : Math.round(value)} ${units[i]}`;
  }
  function bytes(n, decimal = false) {
    const step = decimal ? 1000 : 1024, units = ["B", "KB", "MB", "GB", "TB"];
    let value = n, i = 0;
    while (value >= step && i < units.length - 1) { value /= step; i++; }
    return i === 0 ? `${Math.round(value)} B` : `${value >= 100 ? Math.round(value) : value.toFixed(1)} ${units[i]}`;
  }
  const temp = (c) => `${Math.round(c)}°C`;
  const thousands = (n) => Math.round(n).toLocaleString("en-US");
  const clock = (d) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;

  /** 数字按原字号，单位缩小变淡（与应用里的 UnitText 一致）；整串没有数字时不拆 */
  function u(text) {
    const s = String(text);
    if (!/\d/.test(s)) return esc(s);
    return s.replace(/([^\d.,\-—]+)/g, (m) => `<span class="u">${esc(m)}</span>`);
  }

  // 颜色规则：占用 60% 黄、85% 红；温度 80°C 黄、95°C 红；内存 75% / 90% 或压力告警
  const loadTone = (v, normal = "") => (v >= 0.85 ? "error" : v >= 0.6 ? "warning" : normal);
  const tempTone = (c) => (c >= 95 ? "error" : c >= 80 ? "warning" : "");
  const memTone = (v) => (v >= 0.9 ? "error" : v >= 0.75 ? "warning" : "success");
  const toneClass = (t) => (t ? `c-${t}` : "");

  // ── 图形 ──────────────────────────────────────────────────
  function ring(fraction, cls, size = 56, width = 6) {
    const r = (size - width) / 2, c = 2 * Math.PI * r, f = clamp(fraction, 0, 1);
    return `<svg viewBox="0 0 ${size} ${size}"><circle class="ring-track" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${width}" fill="none"/>
      <circle class="ring-${cls}" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${width}" fill="none" stroke-linecap="round"
      stroke-dasharray="${(c * f).toFixed(2)} ${c.toFixed(2)}" transform="rotate(-90 ${size / 2} ${size / 2})"/></svg>`;
  }
  function pts(values, w, top, span, max, invert = false) {
    const n = Math.max(2, values.length), step = w / (n - 1);
    return values.map((v, i) => [i * step, invert ? top + span * clamp(v / max, 0, 1) : top + span - span * clamp(v / max, 0, 1)]);
  }
  const pathOf = (p) => p.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join("");
  function line(values, { w = 300, h = 24, max = 1, cls = "primary" } = {}) {
    const d = pathOf(pts(values, w, 1, h - 2, max));
    return `<svg class="chart" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" style="height:${h}px"><path class="area-${cls}" d="${d}L${w},${h}L0,${h}Z"/><path class="stroke-${cls}" d="${d}"/></svg>`;
  }
  function dual(down, up, { w = 150, h = 20 } = {}) {
    const max = Math.max(...down, ...up, 64 * 1024) * 1.1;
    const dd = pathOf(pts(down, w, 1, h - 2, max)), du = pathOf(pts(up, w, 1, h - 2, max));
    return `<svg class="chart" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" style="height:${h}px">
      <path class="area-down" d="${dd}L${w},${h}L0,${h}Z"/><path class="stroke-down" d="${dd}"/><path class="stroke-up" d="${du}"/></svg>`;
  }
  /** 上下镜像：上半上传（写入）、下半下载（读取），各自按峰值缩放 */
  function mirrored(up, down, { w = 300, h = 56 } = {}) {
    const mid = h / 2;
    const du = pathOf(pts(up, w, 1, mid - 1, Math.max(...up, 64 * 1024)));
    const dd = pathOf(pts(down, w, mid, mid - 1, Math.max(...down, 64 * 1024), true));
    return `<svg class="chart" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" style="height:${h}px">
      <path class="area-up" d="${du}L${w},${mid}L0,${mid}Z"/><path class="stroke-up" d="${du}"/>
      <path class="area-down" d="${dd}L${w},${mid}L0,${mid}Z"/><path class="stroke-down" d="${dd}"/>
      <line class="mid-line" x1="0" y1="${mid}" x2="${w}" y2="${mid}"/></svg>`;
  }
  const bar = (fraction, color = "var(--os-success)", extra = "") => `<div class="bar ${extra}"><i style="width:${(clamp(fraction, 0, 1) * 100).toFixed(1)}%;background:${color}"></i></div>`;
  const waterline = (parts, total, extra = "") => `<div class="wl ${extra}">${parts.map(([v, color]) => `<i style="width:${(v / total * 100).toFixed(2)}%;background:${color}"></i>`).join("")}</div>`;

  // ── 图标（线性 SVG，不用 emoji） ────────────────────────────
  const I = {
    overview: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M2.5 11a5.5 5.5 0 1 1 11 0"/><path d="m8 11 2.6-3.4"/><circle cx="8" cy="11" r=".8" fill="currentColor"/></svg>',
    cpu: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><rect x="4" y="4" width="8" height="8" rx="1.5"/><path d="M6 1.5v2.5M10 1.5v2.5M6 12v2.5M10 12v2.5M1.5 6H4M1.5 10H4M12 6h2.5M12 10h2.5"/></svg>',
    mem: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><rect x="1.5" y="4" width="13" height="6.5" rx="1.2"/><path d="M4.5 10.5v2.5M8 10.5v2.5M11.5 10.5v2.5"/></svg>',
    net: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M5 13V3M2.5 5.5 5 3l2.5 2.5M11 3v10M8.5 10.5 11 13l2.5-2.5"/></svg>',
    globe: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.2"><circle cx="8" cy="8" r="6.3"/><path d="M1.7 8h12.6M8 1.7c1.8 1.9 2.6 4 2.6 6.3S9.8 12.4 8 14.3C6.2 12.4 5.4 10.3 5.4 8S6.2 3.6 8 1.7z"/></svg>',
    gpu: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"><path d="M8 1.8 14.2 5 8 8.2 1.8 5z"/><path d="M1.8 8 8 11.2 14.2 8M1.8 11 8 14.2l6.2-3.2"/></svg>',
    disk: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M2 9.5 3.8 4h8.4L14 9.5v2.5a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1z"/><path d="M2 9.5h12M4.5 11.3h.01M6.5 11.3h.01" stroke-linecap="round"/></svg>',
    temp: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><path d="M6.5 9.3V3a1.5 1.5 0 0 1 3 0v6.3a3 3 0 1 1-3 0z"/><path d="M8 11.8V6.5" stroke-linecap="round"/></svg>',
    fan: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><circle cx="8" cy="8" r="1.5"/><path d="M8 6.5C8 3 9.5 1.8 11 2.6s1 3.4-3 3.9M9.5 8c3.5 0 4.7 1.5 3.9 3s-3.4 1-3.9-3M8 9.5c0 3.5-1.5 4.7-3 3.9s-1-3.4 3-3.9M6.5 8C3 8 1.8 6.5 2.6 5s3.4-1 3.9 3"/></svg>',
    battery: '<svg viewBox="0 0 18 12" fill="none" stroke="currentColor" stroke-width="1.2"><rect x=".7" y="1.7" width="14.5" height="8.6" rx="2.2"/><rect x="2.4" y="3.4" width="8" height="5.2" rx="1" fill="currentColor" stroke="none"/><path d="M16.6 4.6v2.8" stroke-linecap="round"/></svg>',
    batteryFull: '<svg viewBox="0 0 18 12" fill="none" stroke="currentColor" stroke-width="1.2"><rect x=".7" y="1.7" width="14.5" height="8.6" rx="2.2"/><rect x="2.4" y="3.4" width="11.1" height="5.2" rx="1" fill="currentColor" stroke="none"/><path d="M16.6 4.6v2.8" stroke-linecap="round"/></svg>',
    seal: '<svg viewBox="0 0 24 24"><path fill="currentColor" d="M12 1.5 14.6 3.4l3.2-.2 1 3 2.7 1.8-1 3.1 1 3.1-2.7 1.8-1 3-3.2-.2L12 22.5l-2.6-1.9-3.2.2-1-3-2.7-1.8 1-3.1-1-3.1 2.7-1.8 1-3 3.2.2z"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="m8 12.2 2.6 2.6L16.2 9"/></svg>',
    window: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="2" y="2" width="5" height="5" rx="1"/><rect x="9" y="2" width="5" height="5" rx="1"/><rect x="2" y="9" width="5" height="5" rx="1"/><rect x="9" y="9" width="5" height="5" rx="1"/></svg>',
    gear: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><circle cx="8" cy="8" r="2.2"/><path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8 3.4 3.4"/></svg>',
    cup: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><path d="M2.5 6h9v3.5a3.5 3.5 0 0 1-3.5 3.5H6A3.5 3.5 0 0 1 2.5 9.5z"/><path d="M11.5 7h1a1.5 1.5 0 0 1 0 3h-1M5 1.8v2M8 1.8v2"/></svg>',
    sparkle: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"><path d="M8 1.5 9.3 6.7 14.5 8 9.3 9.3 8 14.5 6.7 9.3 1.5 8l5.2-1.3z"/></svg>',
    camera: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><rect x="1.5" y="4" width="9.5" height="8" rx="1.5"/><path d="m11 7 3.5-2v6L11 9"/></svg>',
    mic: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"><rect x="5.5" y="1.5" width="5" height="8" rx="2.5"/><path d="M3 7.5a5 5 0 0 0 10 0M8 12.5v2"/></svg>',
    history: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M2.5 8a5.5 5.5 0 1 0 1.6-3.9M2.5 2.5v2.2h2.2M8 5v3l2 1.5"/></svg>',
    bars: '<svg viewBox="0 0 16 16" fill="currentColor"><rect x="2" y="7" width="3" height="7" rx="1"/><rect x="6.5" y="4" width="3" height="10" rx="1"/><rect x="11" y="2" width="3" height="12" rx="1"/></svg>',
    info: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.3"><circle cx="8" cy="8" r="6.3"/><path d="M8 7.2v4M8 4.8v.1" stroke-linecap="round"/></svg>',
    chevron: '<svg viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="m2.5 3.8 2.5 2.5 2.5-2.5"/></svg>',
    bolt: '<svg viewBox="0 0 10 14" fill="currentColor" style="width:8px;height:11px"><path d="M6 0 0 8h3.6L3 14l7-8.5H6.3z"/></svg>',
    shield: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1 2.5 3v4.3c0 3.4 2.3 6.4 5.5 7.7 3.2-1.3 5.5-4.3 5.5-7.7V3z"/><path d="m5.5 8.2 1.8 1.8 3.3-3.6" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    home: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.6 1.5 7.3V14h4.6V9.8h3.8V14h4.6V7.3z"/></svg>',
    refresh: '<svg viewBox="0 0 14 14" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" width="12" height="12"><path d="M12 7a5 5 0 1 1-1.5-3.6M12 1.5v2.5H9.5"/></svg>',
  };

  // ── 菜单栏读数：八种风格（对应应用里的 MenuBarRenderer） ─────
  const STYLES = [
    ["stacked", "双行文字", "小标签在上、数值在下，最紧凑"],
    ["inline", "单行文字", "标签与数值同一行，最易读"],
    ["icon", "图标", "用系统图标代替文字标签"],
    ["ring", "圆环", "圆环表示当前占用比例"],
    ["pie", "饼图", "饼图表示当前占用比例"],
    ["history", "柱状历史", "10 根柱子是最近 10 次采样的变化"],
    ["meter", "电量条", "竖向电量条表示当前占用比例"],
    ["dot", "状态圆点", "绿色正常、橙色偏高（60% 以上）、红色很高（85% 以上）"],
  ];
  if (!STYLES.some(([id]) => id === S.style)) S.style = "stacked";
  const MINI = {
    cpu: '<svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" stroke-width="1"><rect x="2.5" y="2.5" width="6" height="6" rx="1"/><path d="M4 .5v2M7 .5v2M4 8.5v2M7 8.5v2M.5 4h2M.5 7h2M8.5 4h2M8.5 7h2"/></svg>',
    mem: '<svg width="13" height="9" viewBox="0 0 13 9" fill="none" stroke="currentColor" stroke-width="1"><rect x=".5" y="1.5" width="12" height="5" rx="1"/><path d="M3 6.5v2M6.5 6.5v2M10 6.5v2"/></svg>',
  };
  function shape(style, value, history) {
    const f = clamp(value, 0, 1);
    switch (style) {
      case "ring": {
        const r = 5.5, c = 2 * Math.PI * r;
        return `<svg width="13" height="13" viewBox="0 0 13 13"><circle cx="6.5" cy="6.5" r="${r}" fill="none" stroke="currentColor" stroke-opacity=".25" stroke-width="2"/><circle cx="6.5" cy="6.5" r="${r}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="${(c * f).toFixed(2)} ${c.toFixed(2)}" transform="rotate(-90 6.5 6.5)"/></svg>`;
      }
      case "pie": {
        const a = f * 2 * Math.PI, x = 6.5 + 6.5 * Math.sin(a), y = 6.5 - 6.5 * Math.cos(a);
        const wedge = f >= 0.999 ? '<circle cx="6.5" cy="6.5" r="6.5" fill="currentColor"/>'
          : `<path d="M6.5 6.5V0A6.5 6.5 0 ${f > 0.5 ? 1 : 0} 1 ${x.toFixed(2)} ${y.toFixed(2)}Z" fill="currentColor"/>`;
        return `<svg width="13" height="13" viewBox="0 0 13 13"><circle cx="6.5" cy="6.5" r="6.5" fill="currentColor" fill-opacity=".25"/>${wedge}</svg>`;
      }
      case "history": {
        const bars = history.slice(-10).map((v, i) => { const h = Math.max(1, 13 * clamp(v, 0, 1)); return `<rect x="${i * 3}" y="${13 - h}" width="2" height="${h}" fill="currentColor"/>`; }).join("");
        return `<svg width="29" height="13" viewBox="0 0 29 13"><rect x="0" y="12" width="29" height="1" fill="currentColor" fill-opacity=".25"/>${bars}</svg>`;
      }
      case "meter": {
        const h = Math.max(3.4, 13 * f);
        return `<svg width="5" height="13" viewBox="0 0 5 13"><rect width="5" height="13" rx="1.5" fill="currentColor" fill-opacity=".25"/><rect y="${13 - h}" width="5" height="${h}" rx="1.5" fill="currentColor"/></svg>`;
      }
      case "dot": return `<svg width="5" height="5" viewBox="0 0 5 5"><circle class="dot-${loadTone(f, "success")}" cx="2.5" cy="2.5" r="2.5"/></svg>`;
      default: return "";
    }
  }
  function metric(key, label, value, history, style) {
    const text = pct(value);
    const stacked = `<span class="mbs__stack"><span class="mbs__label">${label}</span><span class="mbs__value">${text}</span></span>`;
    if (style === "stacked") return `<span class="mbs">${stacked}</span>`;
    if (style === "inline") return `<span class="mbs"><span class="mbs__inline-label">${label}</span><span class="mbs__inline-value">${text}</span></span>`;
    if (style === "icon") return `<span class="mbs">${MINI[key]}<span class="mbs__inline-value">${text}</span></span>`;
    return `<span class="mbs">${shape(style, value, history)}${stacked}</span>`;
  }
  function menubarItems(style, withCup = S.keepAwake) {
    const cup = withCup ? `<span class="mbs" title="防休眠已开启"><svg width="14" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M2.5 6h9v3.5a3.5 3.5 0 0 1-3.5 3.5H6A3.5 3.5 0 0 1 2.5 9.5z"/><path d="M11.5 7h1a1.5 1.5 0 0 1 0 3h-1"/></svg></span>` : "";
    return cup + metric("cpu", "CPU", S.cpu, S.cpuHistory, style) + metric("mem", "RAM", S.mem, S.memHistory, style)
      + `<span class="mbs"><span class="mbs__net"><span><i class="up"></i>${rate(S.up)}</span><span><i class="down"></i>${rate(S.down)}</span></span></span>`;
  }

  // ── 面板实例：首屏、“点开每一项”、网络演示各一个 ───────────
  const TABS = [
    ["overview", "总览", I.overview], ["cpu", "CPU", I.cpu], ["mem", "内存", I.mem], ["net", "网络", I.net],
    ["gpu", "GPU", I.gpu], ["disk", "磁盘", I.disk], ["temp", "温度", I.temp], ["battery", "电池", I.battery],
  ];
  const TITLE = Object.fromEntries(TABS.map(([id, t]) => [id, t]));
  const ICONOF = Object.fromEntries(TABS.map(([id, , icon]) => [id, icon]));
  const PANELS = {
    hero: { el: $("#heroPanel"), tab: "overview", tabs: true, open: true, visible: true },
    stage: { el: $("#stagePanel"), tab: "overview", tabs: true, visible: false },
    net: { el: $("#netDemo"), tab: "net", tabs: false, visible: false },
  };
  Object.values(PANELS).forEach((p) => { if (p.el) p.el.classList.add("os"); });

  const mini = (icon, label, action, pressed = false) => `<button class="osp-mini" type="button" data-action="${action}" aria-label="${label}" title="${label}" aria-pressed="${pressed}">${icon}</button>`;
  function headHTML(id, p) {
    const tabs = p.tabs ? `<div class="osp-tabs" role="tablist">${TABS.map(([tab, title, icon]) =>
      `<button class="osp-tab" type="button" role="tab" data-tab="${tab}" data-panel="${id}" aria-selected="${p.tab === tab}" title="${title}" aria-label="${title}">${icon}</button>`).join("")}</div>` : "";
    if (p.tab === "overview") {
      return `${tabs}<div class="osp-hdr"><span class="osp-hdr__seal">${I.seal}</span><span class="osp-hdr__title">各项指标正常</span><span class="osp-hdr__score">100 分</span>
        <span class="osp-hdr__spacer"></span>${mini(I.window, "在主窗口打开“仪表盘”", "go-cards")}${mini(I.gear, "设置", "go-styles")}</div>
        <div class="osp-machine">M5 Max · 64 GB · macOS 27 · 已运行 3 天</div>`;
    }
    // 每项独立的弹窗带防休眠开关；合并面板的总览底部已有，标签页不重复
    const cup = p.tabs ? "" : mini(I.cup, S.keepAwake ? "关闭防休眠" : "开启防休眠", "awake-toggle", S.keepAwake);
    return `${tabs}<div class="osp-hdr"><span class="osp-hdr__icon">${ICONOF[p.tab]}</span><span class="osp-hdr__title">${TITLE[p.tab]}</span>
      <span class="osp-hdr__spacer"></span>${cup}${mini(ICONOF[p.tab], `在主窗口打开“${TITLE[p.tab]}”`, "go-cards")}${mini(I.gear, "设置", "go-styles")}</div>`;
  }

  function renderPanel(id) {
    const p = PANELS[id];
    if (!p || !p.el) return;
    const body = p.el.querySelector(".osp-body");
    const scroll = body && body.dataset.tab === p.tab ? body.scrollTop : 0;
    const content = p.tab === "overview" ? overview(id, p) : DETAIL[p.tab](id, p);
    p.el.innerHTML = `<div class="osp-head">${headHTML(id, p)}</div>
      <div class="osp-body ${p.tab === "overview" ? "osp-body--overview" : ""}" data-tab="${p.tab}">${content}</div>
      ${p.kaOpen ? keepAwakeMenu(false) : ""}`;
    p.el.querySelector(".osp-body").scrollTop = scroll;
    if (p.kaOpen) placeKeepAwake(p);
  }

  // ── 总览 ──────────────────────────────────────────────────
  function overview(id, p) {
    const memUsed = S.mem * 64;
    const rings = `<div class="oc"><div class="rings">
      ${ringCell(id, "cpu", "CPU", S.cpu, loadTone(S.cpu, "success"), u(temp(S.cpuTemp)), tempTone(S.cpuTemp))}
      ${ringCell(id, "gpu", "GPU", S.gpu, loadTone(S.gpu, "success"), u(temp(S.gpuTemp)), tempTone(S.gpuTemp))}
      ${ringCell(id, "mem", "内存", S.mem, memTone(S.mem), u(`${memUsed.toFixed(1)} GB / 64.0 GB`), "")}
    </div></div>`;
    return rings + meters(id, p) + topProcesses() + tools(id, p);
  }
  function ringCell(id, tab, title, value, tone, detail, detailTone) {
    return `<button class="ring" type="button" data-tab="${tab}" data-panel="${id}" title="查看${title}详情">
      <span class="ring__gauge">${ring(value, tone)}<span class="ring__num"><span>${pctNum(value)}<span class="u">%</span></span></span></span>
      <span class="ring__title">${title}</span><span class="ring__detail ${toneClass(detailTone)}">${detail}</span></button>`;
  }

  /** 磁盘组成：用户数据、系统、启动与恢复、虚拟内存、可清除、空闲 */
  function diskParts() {
    return [["用户数据", 265e9, "var(--os-primary)"], ["系统", 13.7e9, "var(--os-secondary)"], ["启动与恢复", 14e9, "var(--os-neutral)"],
      ["虚拟内存", 2.1e9, "var(--os-warning)"], ["可清除", 1.6e9, "var(--os-primary-soft)"], ["空闲", 1698.6e9, "var(--os-track)"]];
  }

  function meters(id, p) {
    const fanShare = Math.max(S.fans[0] / FAN_MAX[0], S.fans[1] / FAN_MAX[1]);
    const disk = diskParts();
    const head = (tab, icon, title, trailing) => `<div class="cell__head">${icon}<span class="cell__title" data-tab="${tab}" data-panel="${id}">${title}</span><span class="cell__spacer"></span>${trailing}</div>`;
    const battery = `<div class="cell">${head("battery", I.batteryFull, "电池", '<span class="badge">健康 100%</span>')}
      <div class="cell__value"><span class="lhs c-success">100%${I.bolt}</span><span class="rhs">94W · 循环 34 次</span></div>
      <div class="cell__graphic">${bar(1, "var(--os-success)")}</div></div>`;
    const diskCell = `<div class="cell">${head("disk", I.disk, "磁盘", '<span class="badge">2 TB</span>')}
      <div class="cell__value"><span class="lhs"><small>可用</small>${u("1.7 TB")}</span><span class="rhs">已用 15%</span></div>
      <div class="cell__graphic" title="${disk.map(([l, b]) => `${l} ${bytes(b, true)}`).join("&#10;")}">${waterline(disk.map(([, b, c]) => [b, c]), 1995e9)}</div></div>`;
    const net = `<div class="cell">${head("net", I.globe, "网络", '<span class="badge">Wi‑Fi</span>')}
      <div class="cell__value"><span class="lhs"><span style="color:var(--os-down)">↓</span>${u(rate(S.down))}</span><span class="lhs" style="margin-left:auto"><span style="color:var(--os-up)">↑</span>${u(rate(S.up))}</span></div>
      <div class="cell__graphic">${dual(S.downHistory.slice(-30), S.upHistory.slice(-30))}</div></div>`;
    const fan = `<div class="cell">${head("temp", I.fan, "风扇", fanMenu(id, p))}
      <div class="cell__value"><span class="lhs">${u(`${thousands(Math.max(...S.fans))} RPM`)}</span><span class="rhs">转速 ${pct(fanShare)}</span></div>
      <div class="cell__graphic">${line(S.fanHistory.slice(-30), { w: 150, h: 20 })}</div></div>`;
    return `<div class="oc"><div class="meters"><div class="meters__row">${battery}${diskCell}</div><div class="meters__sep"></div><div class="meters__row">${net}${fan}</div></div></div>`;
  }

  function fanMenu(id, p) {
    const title = { auto: "自动", cool: "降温", max: "强冷" }[S.fanMode];
    const list = p.fanOpen ? `<div class="fanmenu__list" role="menu">${[["auto", "自动"], ["cool", "降温"], ["max", "强冷"]].map(([m, t]) =>
      `<button type="button" role="menuitemradio" data-fan="${m}" aria-checked="${S.fanMode === m}">${t}</button>`).join("")}</div>` : "";
    return `<span class="fanmenu"><button class="fanmenu__btn" type="button" data-action="fan-menu" data-panel="${id}" aria-haspopup="menu" aria-expanded="${!!p.fanOpen}" title="风扇档位">${title}${I.chevron}</button>${list}</span>`;
  }

  // 排行固定名次：仍在前几名的保持原位，只更新数值；掉出去的位置才由新上榜的补上
  const order = { top: [], cpuApps: [], memApps: [], net: [], disk: [] };
  function stable(key, ranked, limit, id = (x) => x.name) {
    const top = ranked.slice(0, limit), byId = new Map(top.map((x) => [id(x), x]));
    const previous = order[key].slice(0, limit);
    const slots = previous.map((k) => byId.get(k));
    const kept = new Set(previous.filter((k) => byId.has(k)));
    const newcomers = top.filter((x) => !kept.has(id(x)));
    for (let i = 0; i < slots.length; i++) if (!slots[i] && newcomers.length) slots[i] = newcomers.shift();
    const shown = slots.filter(Boolean).concat(newcomers);
    order[key] = shown.map(id);
    return shown;
  }
  const appIcon = (a) => `<span class="app-icon ai-${a.color}">${esc(a.name[0])}</span>`;
  const shareOf = (a) => (S.sharePerCore ? `${(a.cpu * 100).toFixed(1)}%` : `${(a.cpu / 18 * 100).toFixed(1)}%`);

  function topProcesses() {
    const rows = stable("top", [...APPS].sort((a, b) => b.cpu - a.cpu), 5).map((a) => {
      const machine = a.cpu / 18;
      const hot = machine >= 0.5 ? "hot" : machine >= 0.25 ? "warm" : "";
      return `<div class="tp__row">${appIcon(a)}<span class="tp__name">${esc(a.name)}</span><span class="tp__num ${hot}">${shareOf(a)}</span><span class="tp__num">${bytes(a.mem)}</span><span class="tp__more">···</span></div>`;
    }).join("");
    return `<div class="oc"><div class="tp__head">${I.bars}<span>高占用进程</span><span class="tp__col">CPU</span><span class="tp__col">内存</span><span class="tp__pad"></span></div>${rows}</div>`;
  }

  function tools(id, p) {
    return `<div class="oc"><div class="tools">
      <div class="tools__row">${I.camera}${I.mic}<span class="tools__media">未在使用</span>
        <button class="tool-btn" type="button" data-action="ka" data-panel="${id}" aria-expanded="${!!p.kaOpen}" aria-pressed="${S.keepAwake}">${I.cup}防休眠</button>
        <button class="tool-btn" type="button" data-action="go-clean">${I.sparkle}清理</button></div>
      <div class="tools__sep"></div>
      <div class="tools__label">${I.history}清理记录</div>
      <div class="tools__stats"><div><b>${u("6.8 GB")}</b><span>已清理</span></div><div><b>12</b><span>已卸载</span></div><div><b>31</b><span>已优化</span></div></div>
    </div></div>`;
  }

  // 防休眠浮出菜单：上面两行时长，选一个就开启；下面切换屏幕是否常亮
  const DURATIONS = [[60, "1h", "1 小时"], [120, "2h", "2 小时"], [240, "4h", "4 小时"], [480, "8h", "8 小时"], [720, "12h", "12 小时"], [0, "∞", "不限"]];
  function keepAwakeMenu(staticMenu) {
    const grid = DURATIONS.map(([m, short, long]) => `<button type="button" data-dur="${m}" title="${long}" aria-pressed="${S.keepAwake && S.awakeDur === m}">${short}</button>`).join("");
    const seg = `<div class="seg"><button type="button" data-awake-mode="display" aria-pressed="${S.awakeMode === "display"}">屏幕常亮</button><button type="button" data-awake-mode="system" aria-pressed="${S.awakeMode === "system"}">允许关屏</button></div>`;
    const foot = S.keepAwake
      ? `<div class="ka__foot"><span>${S.awakeEnd ? `${clock(new Date(S.awakeEnd))} 结束` : "一直保持，直到手动关闭"}</span><button type="button" data-action="ka-off">关闭防休眠</button></div>`
      : `<div class="ka__foot"><span>选一个时长就开启</span></div>`;
    return `<div class="ka ${staticMenu ? "ka--static" : ""}" role="dialog" aria-label="防休眠"><div class="ka__grid">${grid}</div>${seg}${foot}</div>`;
  }
  function placeKeepAwake(p) {
    const menu = p.el.querySelector(":scope > .ka"), btn = p.el.querySelector('[data-action="ka"]');
    if (!menu || !btn) return;
    const box = p.el.getBoundingClientRect(), b = btn.getBoundingClientRect();
    const left = clamp(b.left + b.width / 2 - box.left - menu.offsetWidth / 2, 8, box.width - menu.offsetWidth - 8);
    menu.style.left = `${left}px`;
    menu.style.top = `${Math.max(8, b.top - box.top - menu.offsetHeight - 10)}px`;
    menu.style.setProperty("--arrow", `${b.left + b.width / 2 - box.left - left}px`);
  }

  // ── 详情：统一顶部版式 ──────────────────────────────────────
  function hero({ label, value, valueClass = "", split = true, caption = "", stats = [] }) {
    const v = split ? u(value) : esc(value);
    return `<div class="ph"><div class="ph__main"><span class="ph__label">${label}</span><span class="ph__value ${valueClass}">${v}</span>
      ${caption ? `<span class="ph__caption">${caption}</span>` : ""}</div>
      <div class="ph__stats">${stats.map(([l, val, cls = ""]) => `<span class="ph__stat"><span>${l}</span><b class="${cls}" style="font-weight:400">${u(val)}</b></span>`).join("")}</div></div>`;
  }
  const section = (title, body, { trail = "", info = "" } = {}) => `<div class="ps"><div class="ps__head"><span class="ps__title">${title}</span>
    ${info ? `<span class="ps__info" title="${esc(info)}">${I.info}</span>` : ""}<span class="ps__trail">${trail}</span></div>${body}</div>`;
  const irow = (label, value) => `<div class="irow"><span>${label}</span><b>${value}</b></div>`;
  const legend = (color, label, value) => `<span class="legend"><i style="background:${color}"></i>${label} <b>${value}</b></span>`;

  function trend(history) {
    const delta = Math.round((history[history.length - 1] - history[history.length - 31]) * 100);
    if (Math.abs(delta) < 3) return "与 30 秒前持平";
    return delta > 0 ? `比 30 秒前高 ${delta}%` : `比 30 秒前低 ${-delta}%`;
  }
  const status = (v) => (v >= 0.85 ? "满载" : v >= 0.6 ? "繁忙" : v >= 0.25 ? "适中" : "空闲");

  function appList(key, metricKey, total) {
    const ranked = [...APPS].sort((a, b) => (metricKey === "cpu" ? b.cpu - a.cpu : b.mem - a.mem));
    const shown = stable(key, ranked, 6);
    const peak = Math.max(...shown.map((a) => (metricKey === "cpu" ? a.cpu : a.mem)), 1e-6);
    return `<div class="apps">${shown.map((a) => {
      const v = metricKey === "cpu" ? a.cpu : a.mem;
      const text = metricKey === "cpu" ? shareOf(a) : `${bytes(a.mem)} · ${pct(a.mem / total)}`;
      return `<div class="apps__row"><div class="apps__line">${appIcon(a)}<span>${esc(a.name)}</span>${a.procs > 1 ? `<span class="apps__count">${a.procs} 个进程</span>` : ""}<span class="apps__val">${text}</span></div>
        <div class="apps__bar" style="width:calc(${(v / peak * 100).toFixed(1)}% - 24px)"></div></div>`;
    }).join("")}</div>`;
  }

  const DETAIL = {
    cpu() {
      const history = S.cpuHistory.slice(-S.cpuSpan);
      const user = S.cpu * 0.7, sys = S.cpu * 0.3;
      const columns = S.coreHistory.slice(-36);
      const cell = (v) => (v > 0.8 ? "#f59e0b" : `rgba(37, 99, 235, ${(0.08 + clamp(v, 0, 1) * 0.92).toFixed(2)})`);
      const rows = (from, to) => fill(to - from, (_, k) => `<div class="heat__grid" style="grid-template-columns:repeat(${columns.length},1fr)">${columns.map((c) => `<i style="background:${cell(c[from + k])}"></i>`).join("")}</div>`).join("");
      const heat = `<div class="heat"><span class="heat__label">超级核 · 6</span><div style="display:grid;gap:1px">${rows(0, 6)}</div>
        <span class="heat__label">性能核 · 12</span><div style="display:grid;gap:1px">${rows(6, 18)}</div></div>`;
      const legendHeat = `<span class="heat__legend">闲 ${[0.15, 0.4, 0.65, 0.9].map((v) => `<i style="background:rgba(37,99,235,${v})"></i>`).join("")}<i style="background:#f59e0b"></i> 忙</span>`;
      const share = `<span class="picker"><button type="button" data-share="machine" aria-pressed="${!S.sharePerCore}">整机</button><button type="button" data-share="core" aria-pressed="${S.sharePerCore}">单核</button></span>`;
      return `<div class="ph-card">${hero({ label: "CPU 占用", value: pct(S.cpu), caption: trend(S.cpuHistory),
          stats: [["状态", status(S.cpu), toneClass(loadTone(S.cpu))], ["温度", temp(S.cpuTemp), toneClass(tempTone(S.cpuTemp))], ["热状态", "正常"]] })}
        ${line(history, { h: 32 })}
        <div class="row-between"><span class="picker">${[60, 180, 300].map((s) => `<button type="button" data-span="${s}" aria-pressed="${S.cpuSpan === s}">${s / 60} 分钟</button>`).join("")}</span><span class="t3" style="font-size:11px">峰值 ${pct(Math.max(...history))}</span></div>
        ${waterline([[user, "var(--os-primary)"], [sys, "var(--os-secondary)"]], 1, "bar--6")}
        <div class="legends">${legend("var(--os-primary)", "用户", pct(user))}${legend("var(--os-secondary)", "系统", pct(sys))}${legend("var(--os-track)", "空闲", pct(1 - S.cpu))}</div></div>
        ${section("核心热力图", heat, { trail: legendHeat, info: "每行一个核心，每列一次采样，颜色越深越忙" })}
        ${section("按应用汇总", appList("cpuApps", "cpu"), { trail: share, info: "整机：18 个核心全部跑满为 100%；单核：一个核心跑满为 100%，与活动监视器一致" })}`;
    },

    mem() {
      const used = S.mem * 64, free = 64 - used;
      const parts = [["App", used * 0.84, "var(--os-primary)"], ["联动", used * 0.14, "var(--os-secondary)"], ["压缩", used * 0.02, "var(--os-warning)"],
        ["缓存", free * 0.78, "var(--os-primary-soft)"], ["空闲", free * 0.22, "var(--os-track)"]];
      return `<div class="ph-card">${hero({ label: "内存占用", value: pct(S.mem), caption: `已用 ${used.toFixed(1)} GB / 共 64.0 GB`,
          stats: [["可用", `${free.toFixed(1)} GB`], ["压力", "正常"], ["交换", "未使用"]] })}
        ${line(S.memHistory, { h: 24, cls: memTone(S.mem) })}
        <div class="row-between t3" style="font-size:11px"><span>用量走势</span><span>最近 60 秒</span></div></div>
        ${section("内存水位", `${waterline(parts.map(([, v, c]) => [v, c]), 64, "wl--tall")}
          <div class="wl-legend">${parts.map(([l, v, c]) => `<div><i style="background:${c}"></i><span>${l}</span><b>${u(v < 1 ? `${Math.round(v * 1024)} MB` : `${v.toFixed(1)} GB`)}</b></div>`).join("")}</div>`, { trail: u("64.0 GB") })}
        ${section("按应用汇总", appList("memApps", "mem", used * 1024 ** 3), { trail: "内存" })}`;
    },

    net() {
      const probes = S.probes, last = [...probes].reverse().find((v) => v != null);
      const loss = probes.filter((v) => v == null).length / probes.length;
      const cells = probes.map((v) => `<i class="${v == null ? "fail" : v >= 100 ? "slow" : "ok"}"></i>`).join("");
      const apps = stable("net", [...NET_APPS].sort((a, b) => b.down + b.up - a.down - a.up), 5);
      const active = apps.filter((a) => a.down + a.up > 2048);
      const rows = active.map((a) => `<div class="tp__row">${appIcon(a)}<span class="tp__name">${esc(a.name)}</span><span class="tp__num">${rate(a.down)}</span><span class="tp__num">${rate(a.up)}</span></div>`).join("")
        + (active.length < 5 ? `<div class="rest">其他进程暂时没有流量</div>` : "");
      return `<div class="ph-card">${hero({ label: "↓ 下载", value: rate(S.down), caption: "Wi‑Fi · 192.168.1.20",
          stats: [["↑ 上传", rate(S.up)], ["延迟", `${last ? Math.round(last) : "—"} ms`, last >= 100 ? "c-warning" : ""], ["丢包", pct(loss), loss > 0 ? "c-warning" : ""]] })}</div>
        ${section("流量历史", mirrored(S.upHistory, S.downHistory), { trail: `60 秒峰值 <span style="color:var(--os-down)">↓</span> ${rate(Math.max(...S.downHistory))} <span style="color:var(--os-up)">↑</span> ${rate(Math.max(...S.upHistory))}` })}
        ${section("连接探测", `<div class="probe">${cells}</div>`)}
        ${section("接口", irow("接口", "Wi‑Fi（en0）") + irow("状态", '<span class="status">已连接</span>') + irow("物理地址", "a4:83:e7:12:34:56")
          + irow("信号强度", "-42 dBm · 极好") + irow("传输速率", "1200 Mbps") + irow("开机后下载", "18.4 GB") + irow("开机后上传", "2.1 GB"), { trail: I.refresh })}
        ${section("IP 地址", irow("公网 IPv4", "203.0.113.24") + irow("归属地", '<span class="flag"></span>中国大陆 · 上海') + irow("ASN", "AS64500") + irow("网络运营方", "EXAMPLE NETWORK")
          + `<div class="ipbadges"><span class="ipbadge">${I.shield}原生 IP</span><span class="ipbadge">${I.home}住宅 IP</span></div>`)}
        <div class="ps"><div class="collapse"><b>IP 纯净度</b><span class="c-success">94 A</span>${I.chevron}</div></div>
        <div class="ps"><div class="collapse"><b>DNS</b><span>192.168.1.1</span>${I.chevron}</div></div>
        ${section("高占用进程", rows, { trail: '<span class="tp__col">下载</span><span class="tp__col">上传</span>' })}`;
    },

    gpu() {
      const freq = S.gpu < 0.15 ? 338 : Math.round(338 + (1620 - 338) * clamp((S.gpu - 0.1) * 1.4, 0, 1));
      const renderer = clamp(S.gpu * 1.05, 0, 1), tiler = clamp(S.gpu * 0.7, 0, 1);
      const share = (label, v) => `<div class="share">${irow(label, pct(v))}${bar(v, "var(--os-secondary)", "bar--6")}</div>`;
      return `<div class="ph-card">${hero({ label: "GPU 占用", value: pct(S.gpu), caption: "Apple M5 Max · 40 核",
          stats: [["温度", temp(S.gpuTemp), toneClass(tempTone(S.gpuTemp))], ["功耗", `${S.gpuPower.toFixed(1)} W`], ["频率", freq >= 1000 ? `${(freq / 1000).toFixed(2)} GHz` : `${freq} MHz`]] })}</div>
        ${section("使用历史", line(S.gpuHistory, { h: 48, cls: "secondary" }), { trail: "最近 60 秒" })}
        ${section("显卡信息", share("渲染", renderer) + share("拼接", tiler) + irow("占用内存", u(`${(2 + S.gpu * 3).toFixed(1)} GB`)) + irow("平均温度", temp(S.gpuTemp - 1)),
          { info: "渲染是着色与像素处理，拼接是几何与图块划分；GPU 与 CPU 共用统一内存" })}`;
    },

    disk() {
      const parts = diskParts();
      const apps = stable("disk", [...DISK_APPS].sort((a, b) => b.read + b.write - a.read - a.write), 5);
      const peak = Math.max(...apps.map((a) => a.read + a.write), 1);
      const rows = apps.map((a) => `<div class="apps__row"><div class="apps__line">${appIcon(a)}<span>${esc(a.name)}</span><span class="apps__val">读 ${rate(a.read)} · 写 ${rate(a.write)}</span></div>
        <div class="apps__bar" style="width:calc(${((a.read + a.write) / peak * 100).toFixed(1)}% - 24px)"></div></div>`).join("");
      return `<div class="ph-card">${hero({ label: "磁盘占用", value: "15%", caption: "Macintosh HD · 共 2.0 TB",
          stats: [["可用", "1.7 TB"], ["SSD 健康", "100%"], ["已写入", "25.0 TB"]] })}
        ${waterline(parts.map(([, b, c]) => [b, c]), 1995e9, "wl--tall")}
        <div class="wl-legend">${parts.map(([l, b, c]) => `<div><i style="background:${c}"></i><span>${l}</span><b>${u(bytes(b, true))}</b></div>`).join("")}</div></div>
        ${section("读写速度", `<div class="legends">${legend("var(--os-down)", "读取", rate(S.diskRead))}${legend("var(--os-up)", "写入", rate(S.diskWrite))}</div>
          ${mirrored(S.writeHistory, S.readHistory, { h: 48 })}${irow("60 秒峰值", `读 ${rate(Math.max(...S.readHistory))} · 写 ${rate(Math.max(...S.writeHistory))}`)}`, { trail: "所有磁盘合计" })}
        ${section("读写最多的应用", `<div class="apps">${rows}</div>`, { trail: "最近十几秒平均", info: "只含当前用户的进程；数字与条形都是最近十几秒的平均速率" })}`;
    },

    temp(id, p) {
      const sensors = [["CPU", S.cpuTemp], ["GPU", S.gpuTemp], ["内存", S.memTemp], ["电池", S.batteryTemp], ["掌托", S.palmTemp]];
      const rows = sensors.map(([l, c]) => `<div class="share">${irow(l, `${temp(c)} / ${temp(c - 2)}`)}${bar(c / 110, tempTone(c) ? `var(--os-${tempTone(c)})` : "var(--os-primary)", "bar--thin")}</div>`).join("");
      const fans = S.fans.map((rpm, i) => `<div class="share">${irow(`风扇 ${i + 1}`, u(`${thousands(rpm)} / ${thousands(FAN_MAX[i])} RPM`))}${bar(rpm / FAN_MAX[i], "var(--os-primary)", "bar--thin")}</div>`).join("");
      return `<div class="ph-card">${hero({ label: "CPU 最高", value: temp(S.cpuTemp), valueClass: toneClass(tempTone(S.cpuTemp)), caption: "热状态 正常",
          stats: [["GPU", temp(S.gpuTemp)], ["电池", temp(S.batteryTemp)], ["风扇", `${thousands(Math.max(...S.fans))} RPM`]] })}</div>
        ${section("温度", rows, { trail: "最高 / 平均" })}
        ${section("风扇", `${fans}<div class="t3" style="font-size:11px">${S.fanMode === "auto" ? "由 macOS 调节" : "OpenStats 控制中"}</div>`, { trail: fanMenu(id, p) })}`;
    },

    battery() {
      return `<div class="ph-card">${hero({ label: "电量", value: "100%", split: false, valueClass: "c-success", caption: "⚡︎ 已充满",
          stats: [["电源", "94 W"], ["温度", temp(S.batteryTemp)], ["健康", "100%"]] })}
        ${bar(1, "var(--os-success)")}</div>
        ${section("电量历史", line(BATTERY_DAY, { h: 48, cls: "success" }), { trail: "最近 24 小时" })}
        ${section("功耗", `${line(S.powerHistory, { h: 40, max: 50, cls: "warning" })}${irow("整机", `${Math.round(S.power)} W`)}${irow("电源输入", `${Math.round(S.power + 3)} W`)}${irow("电池充电", "0.6 W")}${irow("GPU", `${S.gpuPower.toFixed(1)} W`)}`, { trail: "最近 60 秒" })}
        ${section("电池健康", irow("健康度", "100%") + irow("推算健康度", "100%") + irow("循环次数", "34") + irow("满充 / 设计容量", u("8,611 / 8,579 mAh")) + irow("电压", u("12.82 V")) + irow("电流", u("0.00 A"))
          + `<div class="t3" style="font-size:11px;line-height:1.5">健康度与“系统设置 › 电池”里的最大容量一致；推算健康度是满充容量与设计容量之比，会随使用小幅浮动。低于 80% 时苹果建议更换电池</div>`)}`;
    },
  };

  // ── 首屏面板的位置：吊在状态栏读数下方，靠右但不出屏 ───────
  // 屏幕偏窄时贴右边放，并把面板左侧剩下的宽度交给首屏文字，两者不重叠
  const mbStats = $("#mbStats");
  const heroText = $(".hero");
  const HERO_MIN = 480;
  function placeHero() {
    const p = PANELS.hero;
    if (!p.el) return;
    if (!mbStats || matchMedia("(max-width: 760px)").matches) {
      p.el.style.left = ""; p.el.style.right = "";
      heroText?.style.removeProperty("--hero-room");
      return;
    }
    const r = mbStats.getBoundingClientRect(), width = p.el.offsetWidth || 368, vw = window.innerWidth;
    const textLeft = heroText ? heroText.getBoundingClientRect().left : 0;
    let left = clamp(r.left + r.width / 2 - width / 2, 8, vw - width - 12);
    if (left - textLeft < HERO_MIN + 40) left = vw - width - 12;
    p.el.style.left = `${left}px`;
    p.el.style.right = "auto";
    heroText?.style.setProperty("--hero-room", `${Math.max(280, left - textLeft - 40)}px`);
  }
  function setHeroOpen(open) {
    const p = PANELS.hero;
    p.open = open;
    if (p.el) p.el.classList.toggle("is-closed", !open);
    if (mbStats) mbStats.setAttribute("aria-expanded", String(open));
  }
  function renderMenubar() {
    if (mbStats) mbStats.innerHTML = menubarItems(S.style);
  }

  // ── 桌面小组件：系统概览 ────────────────────────────────────
  const widget = $("#widget");
  function renderWidget() {
    if (!widget) return;
    widget.classList.add("os");
    const g = (title, v, tone) => `<div class="wg-gauge"><div class="wg-gauge__ring">${ring(v, tone, 48, 5)}<b>${pctNum(v)}%</b></div><span>${title}</span></div>`;
    widget.innerHTML = `<div class="wg-head"><b>OpenStats</b><span>${clock(new Date())}</span></div>
      <div class="wg-gauges">${g("CPU", S.cpu, loadTone(S.cpu, "primary"))}${g("内存", S.mem, memTone(S.mem))}${g("磁盘", 0.15, "primary")}${g("电池", 1, "success")}</div>
      <div class="wg-foot">磁盘可用 1.7 TB</div>`;
  }

  // ── “点开每一项”：左边列表 ──────────────────────────────────
  const CARD_DESC = {
    overview: "一张面板看全：三个圆环、电池磁盘网络风扇、高占用进程与常用工具",
    cpu: "占用走势、核心热力图、按应用汇总，整机或单核两种算法",
    mem: "占用、压力与交换，内存水位五段拆开看",
    net: "下载上传、连接探测、接口与 IP、纯净度与 DNS",
    gpu: "功耗、频率、渲染与拼接利用率",
    disk: "按卷拆开看占用，读写速度与 SSD 健康",
    temp: "各处温度与两台风扇，档位一键切换",
    battery: "电量、功耗、满充容量、电压与电流",
  };
  const cardList = $("#cardList");
  function renderCardList() {
    if (!cardList) return;
    cardList.innerHTML = TABS.map(([id, title, icon]) => `<button class="card-tab" type="button" role="tab" data-tab="${id}" data-panel="stage" aria-selected="${PANELS.stage.tab === id}">
      <span class="card-tab__icon">${icon.replace("<svg", '<svg width="16" height="16"')}</span><b>${id === "overview" ? "合并面板总览" : title}</b><span>${CARD_DESC[id]}</span></button>`).join("");
  }

  // ── 菜单栏风格：章节里的选择器、顶部菜单与预览 ──────────────
  const picker = $("#stylePicker"), styleMenu = $("#styleMenu");
  const sysIcons = () => `<svg width="17" height="12" viewBox="0 0 17 12" fill="currentColor"><path d="M8.5 2.3c2.4 0 4.6.9 6.3 2.5l1.1-1.1A10.4 10.4 0 0 0 8.5.7 10.4 10.4 0 0 0 1.1 3.7l1.1 1.1A9 9 0 0 1 8.5 2.3zm0 3.2c1.5 0 2.9.6 4 1.6l1.1-1.1a7.3 7.3 0 0 0-10.2 0l1.1 1.1c1.1-1 2.5-1.6 4-1.6zm0 3.2c.7 0 1.3.3 1.8.7L8.5 11.2 6.7 9.4c.5-.4 1.1-.7 1.8-.7z"/></svg><span>${clock(new Date())}</span>`;
  function renderStylePicker() {
    if (picker) picker.innerHTML = STYLES.map(([id, title]) => `<button class="style-chip" type="button" role="radio" data-style="${id}" aria-checked="${S.style === id}">${title}</button>`).join("");
    if (styleMenu) {
      const label = styleMenu.querySelector(".mb-drop__label");
      styleMenu.innerHTML = "";
      if (label) styleMenu.appendChild(label);
      styleMenu.insertAdjacentHTML("beforeend", STYLES.map(([id, title]) => `<button type="button" role="menuitemradio" data-style="${id}" aria-checked="${S.style === id}"><span class="mb-check"></span>${title}</button>`).join("")
        + `<hr><a role="menuitem" href="#styles">在页面里比较</a>`);
    }
    const caption = $("#styleCaption");
    if (caption) { const s = STYLES.find(([id]) => id === S.style); caption.textContent = `${s[1]}：${s[2]}。整体风格套用到所有项目，也能在设置里给单个项目单独指定。`; }
  }
  function renderStylePreview() {
    const items = `<span style="display:inline-flex;align-items:center;gap:8px">${menubarItems(S.style, false)}</span>${sysIcons()}`;
    const light = $("#stylePreviewLight"), dark = $("#stylePreviewDark");
    if (light) light.innerHTML = items;
    if (dark) dark.innerHTML = items;
  }

  // ── 风扇与防休眠演示 ────────────────────────────────────────
  const FAN_DEMO = { el: $("#fanDemo"), fanOpen: false, visible: false };
  function renderFanDemo() {
    const el = FAN_DEMO.el; if (!el) return;
    el.className = "demo-card os os-panel os-panel--card";
    const share = Math.max(S.fans[0] / FAN_MAX[0], S.fans[1] / FAN_MAX[1]);
    const fans = S.fans.map((rpm, i) => `<div class="share">${irow(`风扇 ${i + 1}`, u(`${thousands(rpm)} / ${thousands(FAN_MAX[i])} RPM`))}${bar(rpm / FAN_MAX[i], "var(--os-primary)", "bar--thin")}</div>`).join("");
    el.innerHTML = `<div class="osp-head"><div class="osp-hdr"><span class="osp-hdr__icon">${I.fan}</span><span class="osp-hdr__title">风扇</span><span class="osp-hdr__spacer"></span>${fanMenu("fan", FAN_DEMO)}</div></div>
      <div class="osp-body" style="overflow:visible">${hero({ label: "最快的风扇", value: `${thousands(Math.max(...S.fans))} RPM`, caption: S.fanMode === "auto" ? "由 macOS 调节" : "OpenStats 控制中",
        stats: [["CPU", temp(S.cpuTemp)], ["GPU", temp(S.gpuTemp)], ["转速", pct(share)]] })}
      <div class="ps" style="margin-top:8px">${fans}${line(S.fanHistory, { h: 28 })}</div></div>`;
  }
  const awakeEl = $("#awakeDemo");
  function renderAwakeDemo() {
    if (!awakeEl) return;
    awakeEl.className = "demo-card os os-panel os-panel--card";
    awakeEl.innerHTML = `<div class="osp-head"><div class="osp-hdr"><span class="osp-hdr__icon">${I.cup}</span><span class="osp-hdr__title">防休眠</span><span class="osp-hdr__spacer"></span>
      <span class="badge" style="${S.keepAwake ? "color:#fff;background:var(--os-primary)" : ""}">${S.keepAwake ? "已开启" : "关闭"}</span></div></div>
      <div class="osp-body" style="overflow:visible">${keepAwakeMenu(true)}</div>`;
  }

  // ── 清理演示 ──────────────────────────────────────────────
  const RULES = [
    { id: "caches", cat: "系统", title: "应用缓存", detail: "10 项 · 8 项使用中", size: 3.5e9, on: true },
    { id: "logs", cat: "系统", title: "应用日志与崩溃报告", detail: "10 项", size: 1.9e7, on: true },
    { id: "safari", cat: "浏览器", title: "Safari 缓存", detail: "1 项", size: 812e6, on: true },
    { id: "chrome", cat: "浏览器", title: "Chrome 缓存", detail: "Chrome 正在运行，已跳过", size: 0, blocked: true },
    { id: "derived", cat: "开发者", title: "Xcode 编译缓存", detail: "6 项", size: 6.2e9, on: true },
    { id: "npm", cat: "开发者", title: "npm 缓存", detail: "1 项", size: 11.8e9, on: false },
  ];
  const cleanEl = $("#cleanDemo");
  function renderClean() {
    if (!cleanEl) return;
    cleanEl.className = "demo-card demo-card--wide os os-panel os-panel--card";
    const selected = RULES.filter((r) => r.on && !r.blocked);
    const total = selected.reduce((a, r) => a + r.size, 0);
    const groups = [...new Set(RULES.map((r) => r.cat))].map((cat) => `<div class="clean__group"><div class="clean__cat">${cat}</div>${RULES.filter((r) => r.cat === cat).map((r) => `
      <div class="clean__row"><button class="check" type="button" role="checkbox" data-rule="${r.id}" aria-checked="${r.on && !r.blocked}" ${r.blocked || S.cleaned ? "disabled" : ""} aria-label="${r.title}"></button>
        <span>${r.title}<small class="${r.blocked ? "c-warning" : ""}">${S.cleaned && r.on ? "已清理" : r.detail}</small></span><span class="size">${r.blocked || (S.cleaned && r.on) ? "" : bytes(r.size, true)}</span></div>`).join("")}</div>`).join("");
    let action;
    if (S.cleaned) action = `<div class="note note--success">已释放 ${bytes(total, true)}（网页演示，没有删除任何文件）</div><div class="actions"><button class="btn" type="button" data-action="rescan">重新扫描</button></div>`;
    else if (S.confirming) action = `<div class="note">将清理 ${selected.length} 类项目，共 ${bytes(total, true)}。缓存与日志直接删除，下载内容移到废纸篓。</div>
      <div class="actions"><button class="btn" type="button" data-action="cancel">取消</button><button class="btn btn--primary" type="button" data-action="confirm">确认清理</button></div>`;
    else action = `<div class="actions"><button class="btn" type="button" data-action="rescan">重新扫描</button><button class="btn btn--primary" type="button" data-action="clean" ${total ? "" : "disabled"}>清理所选 ${bytes(total, true)}</button></div>`;
    cleanEl.innerHTML = `<div class="clean"><div class="clean__top"><b>${u(bytes(S.cleaned ? 0 : total, true))}</b><span>可清理 · 扫描于刚刚</span></div>${groups}${action}</div>`;
  }

  // ── 事件 ──────────────────────────────────────────────────
  function closeMenus() {
    [...Object.values(PANELS), FAN_DEMO].forEach((p) => { p.fanOpen = false; p.kaOpen = false; });
  }
  function renderAll() {
    renderMenubar();
    Object.entries(PANELS).forEach(([id, p]) => { if (id === "hero" ? p.open : p.visible) renderPanel(id); });
    renderWidget();
    if (FAN_DEMO.visible) renderFanDemo();
    renderAwakeDemo();
    renderStylePreview();
  }

  document.addEventListener("click", (event) => {
    const t = event.target.closest("button, [data-tab], [data-action]");
    if (!t || !t.closest(".os, .style-picker, #styleMenu")) {
      // 点在菜单与浮层外面：收起风扇菜单与防休眠浮层
      if (!event.target.closest(".ka, .fanmenu")) {
        const open = [...Object.values(PANELS), FAN_DEMO].some((p) => p.fanOpen || p.kaOpen);
        if (open) { closeMenus(); renderAll(); }
      }
      if (!t) return;
    }
    const panelId = t.dataset.panel;
    const p = panelId === "fan" ? FAN_DEMO : PANELS[panelId];

    if (t.dataset.tab && p) {
      closeMenus();
      p.tab = t.dataset.tab;
      if (panelId === "stage") renderCardList();
      renderPanel(panelId);
      return;
    }
    if (t.dataset.fan) { S.fanMode = t.dataset.fan; closeMenus(); renderAll(); return; }
    if (t.dataset.dur !== undefined) {
      const minutes = Number(t.dataset.dur);
      S.keepAwake = true; S.awakeDur = minutes; S.awakeEnd = minutes ? Date.now() + minutes * 60000 : null;
      renderAll(); return;
    }
    if (t.dataset.awakeMode) { S.awakeMode = t.dataset.awakeMode; renderAll(); return; }
    if (t.dataset.share) { S.sharePerCore = t.dataset.share === "core"; renderAll(); return; }
    if (t.dataset.span) { S.cpuSpan = Number(t.dataset.span); renderAll(); return; }
    if (t.dataset.style) {
      event.preventDefault();
      S.style = t.dataset.style; write("os-style", S.style);
      renderStylePicker(); renderStylePreview(); renderMenubar(); placeHero();
      return;
    }
    if (t.dataset.rule) {
      const rule = RULES.find((r) => r.id === t.dataset.rule);
      if (rule && !rule.blocked) { rule.on = !rule.on; S.confirming = false; renderClean(); }
      return;
    }

    switch (t.dataset.action) {
      case "fan-menu": { const open = !p.fanOpen; closeMenus(); p.fanOpen = open; renderAll(); if (panelId === "fan") renderFanDemo(); break; }
      case "ka": { const open = !p.kaOpen; closeMenus(); p.kaOpen = open; renderPanel(panelId); break; }
      case "ka-off": S.keepAwake = false; S.awakeEnd = null; closeMenus(); renderAll(); break;
      case "awake-toggle": S.keepAwake = !S.keepAwake; S.awakeDur = 0; S.awakeEnd = null; renderAll(); break;
      case "go-cards": location.hash = "#cards"; break;
      case "go-styles": location.hash = "#styles"; break;
      case "go-clean": location.hash = "#cleanup"; break;
      case "clean": S.confirming = true; renderClean(); break;
      case "cancel": S.confirming = false; renderClean(); break;
      case "confirm": S.confirming = false; S.cleaned = true; renderClean(); break;
      case "rescan": S.cleaned = false; S.confirming = false; renderClean(); break;
      default: break;
    }
  });

  if (mbStats) mbStats.addEventListener("click", () => {
    setHeroOpen(!PANELS.hero.open);
    if (PANELS.hero.open) { placeHero(); renderPanel("hero"); }
  });
  const dockOpenStats = $("#dockOpenStats");
  if (dockOpenStats) dockOpenStats.addEventListener("click", () => {
    setHeroOpen(true); placeHero(); renderPanel("hero");
    window.scrollTo({ top: 0, behavior: "smooth" });
  });
  window.addEventListener("resize", placeHero);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && [...Object.values(PANELS), FAN_DEMO].some((p) => p.fanOpen || p.kaOpen)) { closeMenus(); renderAll(); }
  });

  // 只刷新看得见的部件，滚出视野就不画
  if ("IntersectionObserver" in window) {
    const watch = (el, target) => { if (el) new IntersectionObserver(([entry]) => { target.visible = entry.isIntersecting; }).observe(el); };
    watch(PANELS.stage.el, PANELS.stage);
    watch(PANELS.net.el, PANELS.net);
    watch(FAN_DEMO.el, FAN_DEMO);
  } else {
    PANELS.stage.visible = PANELS.net.visible = FAN_DEMO.visible = true;
  }

  // ── 启动 ──────────────────────────────────────────────────
  renderCardList();
  renderStylePicker();
  renderClean();
  renderFanDemo();
  Object.keys(PANELS).forEach(renderPanel);
  renderAll();
  placeHero();
  setHeroOpen(true);
  setInterval(() => {
    if (document.hidden) return;
    tick();
    renderAll();
  }, 1000);
})();
