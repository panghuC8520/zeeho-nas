// 用 DevTools 协议截图（可先执行一段 JS，比如切换 tab）
// 用法: node tools\shot.js <url> <out.png> ["js"] [width] [height]
const fs = require('fs');
const url = process.argv[2];
const out = process.argv[3];
const js = process.argv[4] || '';
const width = Number(process.argv[5] || 1440);
const height = Number(process.argv[6] || 900);
const port = process.env.CDP_PORT || '9222';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  let targets = null;
  for (let i = 0; i < 30; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/list`);
      targets = await r.json();
      if (targets.some((t) => t.type === 'page')) break;
    } catch (e) {}
    await sleep(300);
  }
  const page = (targets || []).find((t) => t.type === 'page');
  if (!page) throw new Error('没有可调试页面');

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let seq = 0;
  const pending = new Map();
  ws.addEventListener('message', (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  });
  const send = (method, params) => new Promise((res) => {
    const id = ++seq; pending.set(id, res);
    ws.send(JSON.stringify({ id, method, params: params || {} }));
  });

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url });
  await sleep(4500);
  if (js) {
    const r = await send('Runtime.evaluate', { expression: js, returnByValue: true, awaitPromise: true });
    if (r.result && r.result.exceptionDetails) console.error('JS 错误:', JSON.stringify(r.result.exceptionDetails.text));
    await sleep(2500);
  }
  const shot = await send('Page.captureScreenshot', { format: 'png' });
  fs.writeFileSync(out, Buffer.from(shot.result.data, 'base64'));
  console.log(`${out} -> ${fs.statSync(out).size} B`);
  ws.close();
}
main().catch((e) => { console.error('ERR', e.message); process.exit(1); });
