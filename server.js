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
  if (!Object.keys(headers).some((k) => k.toLowerCase() === 'content-type')) {
    headers['Content-Type'] = /^\{|^\[/.test(out.body.trim()) ? 'application/json; charset=utf-8' : 'text/html; charset=utf-8';
  }
  headers['Content-Length'] = Buffer.byteLength(out.body || '');
  try {
    res.writeHead(out.status || 200, headers);
    res.end(out.body || '');
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
