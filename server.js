#!/usr/bin/env node
/**
 * ZEEHO 面板 · NAS 包装层（Loon/Surge 兼容 Runtime）
 * ------------------------------------------------------------------------------
 * 原脚本 script/zeeho_box_enhanced.js 是写给 Loon / Surge / QX / Shadowrocket 的
 * 重写脚本：它靠 $request / $done / $httpClient / $persistentStore / $notification
 * 这几个宿主全局对象工作。本文件把这些对象用 Node.js 实现出来，并起一个 HTTP
 * 服务，让面板（http://<NAS_IP>:8080/）在任何浏览器里都能用，签到由容器内定时器
 * 驱动，不再依赖手机常驻代理。
 *
 * 依赖：Node >= 18（用内置 fetch）。无第三方 npm 依赖。
 */
'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

// ============================== 配置 ==============================
const PORT = Number(process.env.PORT || 8080);
const BIND = process.env.HOST || '0.0.0.0';
const SCRIPT_FILE = process.env.ZEEHO_SCRIPT || path.join(__dirname, 'script', 'zeeho_box_enhanced.js');
const DATA_DIR = process.env.ZEEHO_DATA || path.join(__dirname, 'data');
const PANEL_AUTH = (process.env.PANEL_AUTH || '').trim();          // 可选：user:pass
const REQ_TIMEOUT_MS = Number(process.env.REQ_TIMEOUT_MS || 180000); // 单次脚本执行上限
const MAX_BODY = 8 * 1024 * 1024;
const DEBUG = process.env.DEBUG === '1';
const CRON_ENABLE = (process.env.CRON_ENABLE || '1') === '1';
const CRON_TIME = /^\d{1,2}:\d{2}$/.test(process.env.CRON_TIME || '') ? process.env.CRON_TIME : '07:05';
const TZ = process.env.TZ || 'Asia/Shanghai';

if (!fs.existsSync(SCRIPT_FILE)) {
  console.error(`[fatal] 找不到脚本: ${SCRIPT_FILE}\n请先执行 bash update-script.sh 或挂载脚本文件。`);
  process.exit(1);
}
const SOURCE = fs.readFileSync(SCRIPT_FILE, 'utf8');
const SCRIPT_MTIME = fs.statSync(SCRIPT_FILE).mtime.toISOString();

// ============================== 持久化 ==============================
fs.mkdirSync(DATA_DIR, { recursive: true });
const STORE_FILE = path.join(DATA_DIR, 'store.json');
let store = {};
try {
  store = JSON.parse(fs.readFileSync(STORE_FILE, 'utf8')) || {};
} catch (e) {
  store = {};
}
function storeFlush() {
  const tmp = STORE_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2), 'utf8');
  fs.renameSync(tmp, STORE_FILE);
}
function storeRead(key) {
  const k = String(key);
  return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null;
}
function storeWrite(value, key) {
  if (value === undefined || value === null) delete store[String(key)];
  else store[String(key)] = String(value);
  storeFlush();
  return true;
}

// ============================== 日志环形缓冲 ==============================
const ring = [];
function pushLog(s) {
  if (typeof s !== 'string') s = String(s);
  if (s.length > 2000) s = s.slice(0, 2000) + ' …(truncated)';
  ring.push(`${new Date().toISOString()} ${s}`);
  if (ring.length > 800) ring.shift();
  if (DEBUG) process.stdout.write(`[zeeho] ${s}\n`);
}

// ============================== 作者信息清理 ==============================
// 只处理输出给浏览器的 HTML，不改上游脚本本体（update-script.sh 拉新版也不会丢改动）。
// STRIP_AUTHOR=0 可关掉。
const STRIP_AUTHOR = (process.env.STRIP_AUTHOR || '1') !== '0';
const AUTHOR_RULES = [
  // 设置页「关于」卡片：邮箱行 / GitHub 仓库行 / 爱发电行（连同其后的分隔线）
  [/'\s*<a href="mailto:mlink798@outlook\.com"[\s\S]{0,600}?<\/a>'\s*\+\s*'<div style="height:1px;background:var\(--line\);margin:0 16px"><\/div>'\s*\+/g, "''+"],
  [/'\s*<a href="https:\/\/github\.com\/cluck798\/ZEEHO"[^']*<\/a>'\s*\+\s*'<div style="height:1px;background:var\(--line\);margin:0 16px"><\/div>'\s*\+/g, "''+"],
  [/'\s*<a href="https:\/\/afdian\.com\/a\/lucky798"[^']*<\/a>'\s*\+\s*'<div style="height:1px;background:var\(--line\);margin:0 16px"><\/div>'\s*\+/g, "''+"],
  // 首页 footer：作者 lucky · GitHub · 爱发电 · 仅供学习研究
  [/'<br><a class="link" href="https:\/\/github\.com\/cluck798\/ZEEHO"[^']*<\/a> · <a class="link" href="https:\/\/afdian\.com\/a\/lucky798"[^']*<\/a> · 仅供学习研究<\/div>'/g, "'</div>'"],
  // 设置页 footer：爱发电 · afdian.com/a/lucky798
  [/'<br><a class="link" href="https:\/\/afdian\.com\/a\/lucky798"[^']*<\/a><\/div>'/g, "'</div>'"],
  // 单账号版：GitHub 仓库 / 爱发电 / Issues 三个 link-row
  [/'<div class="link-row" onclick="openExternal\([^)]*?(?:github\.com\/cluck798|afdian\.com\/a\/lucky798)[^)]*?\)">[\s\S]*?<\/div>'\s*\+/g, "''+"],
  // 单账号版抓包提示里的仓库地址
  [/<div class="hint">仓库：github\.com\/cluck798\/ZEEHO · /g, '<div class="hint">'],
  // 骑行页脚注的算法署名
  [/压弯\/急刹算法移植自 Zeeho SpeedHunter（AGPL-3\.0），仅供学习研究/g, '压弯/急刹为本地重算'],
  // 开关已改成即时保存，提示文案同步
  [/修改后点击页面底部「保存配置」生效。/g, '开关改动即时保存。']
];
let stripHits = 0;
function stripAuthor(html) {
  if (!STRIP_AUTHOR || typeof html !== 'string') return html;
  let out = html;
  for (const [re, rep] of AUTHOR_RULES) {
    out = out.replace(re, () => { stripHits++; return rep; });
  }
  return out;
}

// ============================== 面板补丁（开关即时保存） ==============================
// 上游面板的开关是「草稿态」：拨完必须点页面底部「保存配置」，而 60 秒自动刷新会重渲染
// 设置页把未保存的改动冲掉，看起来就是「一刷新就关」。这里注入一小段脚本：
// 开关/时间一改动立刻 POST /api/save-config，并持续把服务端值同步回控件。
const PANEL_PATCH_ON = (process.env.PANEL_PATCH || '1') !== '0';
const PANEL_PATCH = `<script data-zh-patch="1">
(function(){
  if (location.search.indexOf('demo') >= 0) return;
  var CFG = null;
  function tip(msg){
    try { if (typeof window.toast === 'function') { window.toast(msg,'ok'); return; } } catch(e){}
    var d = document.createElement('div');
    d.textContent = msg;
    d.style.cssText = 'position:fixed;left:50%;bottom:26px;transform:translateX(-50%);background:#0E1628;color:#EAF1FB;border:1px solid rgba(146,170,205,.25);padding:10px 16px;border-radius:12px;font-size:13px;z-index:99999;box-shadow:0 8px 24px rgba(0,0,0,.45)';
    document.body.appendChild(d);
    setTimeout(function(){ d.remove(); }, 1600);
  }
  function getCfg(){
    if (CFG) return Promise.resolve(CFG);
    return fetch('/api/config', { cache:'no-store' })
      .then(function(r){ return r.json(); })
      .then(function(j){ if (j && j.config) CFG = j.config; return CFG; })
      .catch(function(){ return null; });
  }
  function save(patch, label){
    return getCfg().then(function(base){
      var next = Object.assign({}, base || {}, patch);
      CFG = next;
      return fetch('/api/save-config', {
        method:'POST',
        headers:{ 'Content-Type':'application/json' },
        body: JSON.stringify(next)
      }).then(function(r){ return r.json(); })
        .then(function(res){ if (res && res.ok) tip(label + '已保存'); })
        .catch(function(){ tip(label + '保存失败'); });
    });
  }
  function syncUI(){
    getCfg().then(function(c){
      if (!c) return;
      var a = document.getElementById('auto_signin');
      if (a && a.checked !== (c.autoSignin === true)) a.checked = (c.autoSignin === true);
      var m = document.getElementById('vehicle_monitor');
      if (m && m.checked !== (c.vehicleMonitor === true)) m.checked = (c.vehicleMonitor === true);
      var p = document.getElementById('vehicle_alert_push');
      if (p && p.checked !== (c.vehicleAlertPush !== false)) p.checked = (c.vehicleAlertPush !== false);
      var t = document.getElementById('cfg_signin_time');
      if (t && !t.value) t.value = c.autoSigninTime || '07:00';
    });
  }
  function bind(){
    var map = [
      ['auto_signin','autoSignin','定时签到'],
      ['vehicle_monitor','vehicleMonitor','车辆状态监控'],
      ['vehicle_alert_push','vehicleAlertPush','车辆提醒推送']
    ];
    map.forEach(function(it){
      var el = document.getElementById(it[0]);
      if (!el || el.__zhBound) return;
      el.__zhBound = true;
      el.addEventListener('change', function(){
        var patch = {}; patch[it[1]] = el.checked;
        save(patch, it[2]);
      });
    });
    var ti = document.getElementById('cfg_signin_time');
    if (ti && !ti.__zhBound) {
      ti.__zhBound = true;
      ti.addEventListener('change', function(){ save({ autoSigninTime: ti.value || '07:00' }, '签到时间'); });
    }
  }
  function tick(){ try { bind(); syncUI(); } catch(e){} }
  try {
    if (typeof window.renderCfg === 'function' && !window.renderCfg.__zhWrapped) {
      var orig = window.renderCfg;
      var wrapped = function(){ var r = orig.apply(this, arguments); setTimeout(tick, 0); return r; };
      wrapped.__zhWrapped = true;
      window.renderCfg = wrapped;
    }
  } catch(e){}
  setInterval(tick, 1500);
  document.addEventListener('DOMContentLoaded', tick);
  tick();
  // 深链：?zh_tab=cfg|points|vehicle|ride|logs 可直接打开对应页（方便收藏 / 截图 / 排查）
  try {
    var mt = /[?&]zh_tab=([a-z]+)/.exec(location.search);
    if (mt && typeof window.switchTab === 'function') setTimeout(function(){ try { window.switchTab(mt[1]); } catch(e){} }, 400);
  } catch(e){}
})();
</script>`;

// ============================== 桌面端适配（≥1024px） ==============================
// 上游面板是移动端布局：main 最大 680px、底部 tab 栏、卡片单列。这里在宽屏下换成
// 「左侧竖排导航 + 宽内容区 + 卡片双列」，移动端（<1024px）完全不受影响。
const PC_UI_ON = (process.env.PC_UI || '1') !== '0';
const PC_CSS = `<style data-zh-pc="1">
@media (min-width:1024px){
  body{--zh-rail:212px}
  /* 内容区变宽 */
  #app{display:flex!important;flex-direction:column!important;min-height:100vh}
  main{width:100%;max-width:1240px!important;margin:0 auto;padding-left:26px;padding-right:26px}
  /* 底部 tab 栏 → 左侧竖排导航 */
  nav.tabbar{
    left:0;right:auto;top:0;bottom:0;width:var(--zh-rail);height:100vh;
    flex-direction:column;align-items:stretch;justify-content:flex-start;
    gap:4px;padding:92px 12px 22px;border-top:none;border-right:1px solid var(--line);
    background:rgba(9,14,28,.72);-webkit-backdrop-filter:blur(20px);backdrop-filter:blur(20px);
  }
  nav.tabbar .tab{
    flex:0 0 auto;flex-direction:row;justify-content:flex-start;gap:11px;
    padding:11px 13px;border-radius:12px;font-size:14px;font-weight:700;
  }
  nav.tabbar .tab svg{width:19px;height:19px;flex-shrink:0}
  nav.tabbar .tab:hover{background:var(--card);color:var(--txt)}
  nav.tabbar .tab.on{background:var(--card2);color:var(--brand)}
  nav.tabbar .tab.on:hover{background:var(--card2)}
  nav.tabbar .t-ind{display:none}
  #app{padding-left:var(--zh-rail)}
  /* 顶部栏与浮层让位 */
  header.app-header{position:sticky;top:0;padding-left:26px;padding-right:26px}
  .signin-fab{right:26px;bottom:26px}
  /* 首页账号卡片：多列 */
  #pageHome{width:100%;display:grid;grid-template-columns:repeat(auto-fill,minmax(430px,1fr));gap:16px;align-items:start}
  #pageHome>.foot,#pageHome>.acc-chips,#pageHome>.hero{grid-column:1/-1}
  /* 设置页：两列 */
  #pageCfg{width:100%;display:grid;grid-template-columns:repeat(auto-fill,minmax(470px,1fr));gap:16px;align-items:start}
  #pageCfg>.section-title,#pageCfg>.foot,#pageCfg>.btn-row,#pageCfg>.acc-chips{grid-column:1/-1}
  /* 积分 / 车辆 / 骑行页：适当放大网格 */
  .pt-grid,.rt-grid,.rt-grid3,.ctrl-grid{gap:12px}
  /* 积分日历在宽屏下别被拉成大色块 */
  #pagePoints .cal-grid{grid-auto-rows:56px}
  #pagePoints .cal-d{height:56px;min-height:0;border-radius:10px}
  /* 车辆页两列 */
  #pageVehicle{width:100%;display:grid;grid-template-columns:repeat(auto-fill,minmax(470px,1fr));gap:16px;align-items:start}
  #pageVehicle>.acc-chips,#pageVehicle>.opt-row,#pageVehicle>.foot{grid-column:1/-1}
  /* 骑行页两列 */
  #pageRide{width:100%;display:grid;grid-template-columns:repeat(auto-fill,minmax(470px,1fr));gap:16px;align-items:start}
  #pageRide>.acc-chips,#pageRide>.foot{grid-column:1/-1}
  /* 卡片悬停反馈 */
  .acc-card,.cfg-panel,.panel-card{transition:border-color .18s,transform .18s}
  .acc-card:hover,.cfg-panel:hover,.panel-card:hover{border-color:var(--line2)}
  /* 细滚动条 */
  ::-webkit-scrollbar{width:10px;height:10px}
  ::-webkit-scrollbar-thumb{background:rgba(146,170,205,.22);border-radius:8px}
  ::-webkit-scrollbar-track{background:transparent}
}
@media (min-width:1600px){
  main{max-width:1460px!important}
  #pageHome{grid-template-columns:repeat(auto-fill,minmax(460px,1fr))}
}
</style>`;

// ============================== $httpClient ==============================
function sanitizeHeaders(h) {
  const out = {};
  if (!h || typeof h !== 'object') return out;
  for (const k of Object.keys(h)) {
    const v = h[k];
    if (v === undefined || v === null) continue;
    out[k] = String(v);
  }
  return out;
}

function httpRequest(method, opts, cb) {
  const o = typeof opts === 'string' ? { url: opts } : (opts || {});
  const url = o.url;
  const m = String(method || 'GET').toUpperCase();
  if (!url) { cb('missing url', null, ''); return; }

  const headers = sanitizeHeaders(o.headers);
  const init = { method: m, headers, redirect: 'follow' };
  if (o.body !== undefined && o.body !== null && m !== 'GET' && m !== 'HEAD') {
    init.body = typeof o.body === 'string' ? o.body : JSON.stringify(o.body);
    const hasLen = Object.keys(headers).some((k) => k.toLowerCase() === 'content-length');
    if (!hasLen) headers['Content-Length'] = Buffer.byteLength(init.body);
  }
  // 脚本传的 timeout：Loon/Surge 侧单位是秒
  const tmo = Number(o.timeout) > 0 ? Number(o.timeout) * 1000 : REQ_TIMEOUT_MS;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), Math.min(tmo, REQ_TIMEOUT_MS));
  init.signal = ac.signal;

  fetch(url, init)
    .then(async (r) => {
      const body = await r.text();
      const rh = {};
      r.headers.forEach((v, k) => { rh[k] = v; });
      cb(null, { status: r.status, statusCode: r.status, headers: rh, body }, body);
    })
    .catch((e) => cb(String((e && e.message) || e), null, ''))
    .finally(() => clearTimeout(timer));
}

const $httpClient = {
  get: (o, cb) => httpRequest('GET', o, cb),
  post: (o, cb) => httpRequest('POST', o, cb),
  put: (o, cb) => httpRequest('PUT', o, cb),
  delete: (o, cb) => httpRequest('DELETE', o, cb),
  head: (o, cb) => httpRequest('HEAD', o, cb),
  patch: (o, cb) => httpRequest('PATCH', o, cb),
};

// ============================== 脚本执行 ==============================
function runScript(reqInfo) {
  return new Promise((resolve) => {
    let settled = false;
    let deadline = null;
    const finish = (payload) => {
      if (settled) return;
      settled = true;
      if (deadline) clearTimeout(deadline);
      resolve(payload);
    };

    const sandboxConsole = {
      log: (...a) => pushLog(a.join(' ')),
      info: (...a) => pushLog(a.join(' ')),
      warn: (...a) => pushLog('[warn] ' + a.join(' ')),
      error: (...a) => pushLog('[error] ' + a.join(' ')),
      debug: () => {},
    };

    const ctx = {
      // 宿主注入
      $request: reqInfo,
      $response: undefined,
      $persistentStore: { read: storeRead, write: storeWrite },
      $httpClient,
      $notification: {
        post: (title, subtitle, body) =>
          pushLog(`[notify] ${title || ''} | ${subtitle || ''} | ${body || ''}`),
      },
      $done: (obj) => {
        if (!obj || typeof obj !== 'object') return finish({ status: 204, headers: {}, body: '' });
        if (obj.response && typeof obj.response === 'object') {
          const r = obj.response;
          return finish({
            status: Number(r.status || r.statusCode || 200),
            headers: r.headers || {},
            body: typeof r.body === 'string' ? r.body : (r.body == null ? '' : JSON.stringify(r.body)),
          });
        }
        if (typeof obj.body === 'string') return finish({ status: 200, headers: {}, body: obj.body });
        // $done({}) —— 代理语义是「放行原请求」，这里当成空响应
        return finish({ status: 204, headers: {}, body: '' });
      },
      $loon: {},              // 让脚本内 Env 判定为 Loon：存储走 $persistentStore，HTTP 走 $httpClient
      console: sandboxConsole,

      // Node 内置能力（vm 上下文里没有这些）
      URL, URLSearchParams, TextDecoder, TextEncoder, atob, btoa,
      Buffer, setTimeout, clearTimeout, setInterval, clearInterval, queueMicrotask,
      fetch, AbortController, performance, crypto,
    };

    deadline = setTimeout(() => {
      pushLog(`[timeout] ${reqInfo.method} ${reqInfo.url}`);
      finish({ status: 504, headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify({ ok: false, error: '脚本执行超时' }) });
    }, REQ_TIMEOUT_MS);
    if (deadline.unref) deadline.unref();

    try {
      vm.createContext(ctx);
      vm.runInContext(SOURCE, ctx, { filename: 'zeeho_box_enhanced.js', timeout: 60000 });
    } catch (e) {
      pushLog(`[exception] ${(e && e.stack) || e}`);
      finish({
        status: 500,
        headers: { 'Content-Type': 'application/json; charset=utf-8' },
        body: JSON.stringify({ ok: false, error: String((e && e.message) || e) }),
      });
    }
  });
}

// ============================== HTTP 服务 ==============================
function authOk(req) {
  if (!PANEL_AUTH) return true;
  const h = req.headers.authorization || '';
  const want = 'Basic ' + Buffer.from(PANEL_AUTH, 'utf8').toString('base64');
  return h === want;
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new Error('body too large')); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const urlPath = req.url || '/';

  // 健康检查 & 自检接口不鉴权
  if (urlPath === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('ok');
    return;
  }
  if (urlPath.startsWith('/__diagnostics')) {
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({
      ok: true,
      node: process.version,
      tz: TZ,
      script: SCRIPT_FILE,
      scriptMtime: SCRIPT_MTIME,
      storeKeys: Object.keys(store),
      cron: CRON_ENABLE ? CRON_TIME : 'off',
      logs: ring.slice(-60),
    }, null, 2));
    return;
  }

  if (!authOk(req)) {
    res.writeHead(401, { 'WWW-Authenticate': 'Basic realm="ZEEHO"' });
    res.end('auth required');
    return;
  }

  let body = '';
  try {
    body = await readBody(req);
  } catch (e) {
    res.writeHead(413); res.end('too large'); return;
  }

  const host = req.headers.host || `127.0.0.1:${PORT}`;
  const reqInfo = {
    url: `http://${host}${urlPath}`,
    method: (req.method || 'GET').toUpperCase(),
    headers: sanitizeHeaders(req.headers),
    body,
  };

  const started = Date.now();
  const out = await runScript(reqInfo);
  const headers = sanitizeHeaders(out.headers);
  delete headers['content-encoding'];
  delete headers['Content-Encoding'];
  let respBody = out.body || '';
  const ctKey = Object.keys(headers).find((k) => k.toLowerCase() === 'content-type');
  const ctVal = ctKey ? String(headers[ctKey]) : (/^\{|^\[/.test(respBody.trim()) ? 'application/json; charset=utf-8' : 'text/html; charset=utf-8');
  if (/text\/html/i.test(ctVal)) {
    const before = respBody.length;
    respBody = stripAuthor(respBody);
    if (respBody.length !== before) pushLog(`[strip] 作者信息已清理 ${before - respBody.length}B (${urlPath})`);
    // 桌面端适配 + 开关即时保存补丁：只注入到含设置页的看板 HTML
    const needPc = PC_UI_ON && respBody.indexOf('data-zh-pc') < 0;
    const needPatch = PANEL_PATCH_ON && respBody.indexOf('data-zh-patch') < 0;
    if ((needPc || needPatch) && respBody.indexOf('id="pageCfg"') >= 0) {
      const extra = (needPc ? PC_CSS : '') + (needPatch ? PANEL_PATCH : '');
      const end = respBody.lastIndexOf('</body>');
      // 看板 HTML 是片段（没有 </body>，结尾是 <!--__JS5__--> 占位），没有就追加到末尾
      respBody = end >= 0 ? (respBody.slice(0, end) + extra + respBody.slice(end)) : (respBody + extra);
      pushLog(`[patch] 已注入 桌面适配=${needPc} 开关保存=${needPatch} (${urlPath})`);
    }
  }
  if (!ctKey) headers['Content-Type'] = ctVal;
  headers['Content-Length'] = Buffer.byteLength(respBody);
  try {
    res.writeHead(out.status || 200, headers);
    res.end(respBody);
  } catch (e) {
    pushLog(`[resp-error] ${e && e.message}`);
    try { res.writeHead(500); res.end('internal error'); } catch (_) {}
  }
  pushLog(`${reqInfo.method} ${urlPath} -> ${out.status} ${Buffer.byteLength(out.body || '')}B ${Date.now() - started}ms`);
});

// ============================== 每日签到定时器 ==============================
function nextDelayFor(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  const now = new Date();
  const next = new Date(now);
  next.setHours(h, m, 0, 0);
  if (next.getTime() <= now.getTime()) next.setDate(next.getDate() + 1);
  return next.getTime() - now.getTime();
}

async function cronSignin() {
  const host = `127.0.0.1:${PORT}`;
  const started = Date.now();
  const out = await runScript({
    url: `http://${host}/api/run-signin`,
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ all: true }),
  });
  let summary = out.body || '';
  try {
    const j = JSON.parse(summary);
    const rs = Array.isArray(j.results) ? j.results : [];
    summary = rs.map((r) => `${r.userName || r.userId || '?'}:${r.ok === false ? '失败' : '成功'}`).join(', ') || '无账号';
  } catch (e) {}
  pushLog(`[cron] 签到完成 ${Date.now() - started}ms ${summary}`);
}

function scheduleCron() {
  if (!CRON_ENABLE) { pushLog('[cron] 未启用'); return; }
  const tick = async () => {
    try { await cronSignin(); } catch (e) { pushLog(`[cron] 异常 ${e && e.message}`); }
    setTimeout(tick, nextDelayFor(CRON_TIME));
  };
  const d = nextDelayFor(CRON_TIME);
  pushLog(`[cron] 下次签到 ${Math.round(d / 60000)} 分钟后（每天 ${CRON_TIME}）`);
  setTimeout(tick, d);
}

// ============================== 启动 ==============================
process.env.TZ = TZ;
server.listen(PORT, BIND, () => {
  pushLog(`ZEEHO 面板已启动: http://${BIND}:${PORT}/  (TZ=${TZ})`);
  console.log(`\n  ZEEHO 面板 → http://${BIND === '0.0.0.0' ? '<NAS_IP>' : BIND}:${PORT}/`);
  if (PANEL_AUTH) console.log(`  已开启 Basic Auth（PANEL_AUTH 已设置）`);
  scheduleCron();
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    pushLog(`收到 ${sig}，保存并退出`);
    try { storeFlush(); } catch (e) {}
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000);
  });
}
