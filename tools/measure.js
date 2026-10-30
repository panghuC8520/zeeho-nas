// 用 DevTools 协议量页面的真实布局（无头 Edge 需先带 --remote-debugging-port=9222 启动）
// 用法: node tools\measure.js "http://127.0.0.1:18098/?demo" "<js 表达式>"
const url = process.argv[2];
const expr = process.argv[3] || 'document.title';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  let targets = null;
  for (let i = 0; i < 30; i++) {
    try {
      const port = process.env.CDP_PORT || '9222';
      const r = await fetch('http://127.0.0.1:' + port + '/json/list');
      targets = await r.json();
      if (targets.some((t) => t.type === 'page')) break;
    } catch (e) { /* retry */ }
    await sleep(300);
  }
  const page = (targets || []).find((t) => t.type === 'page');
  if (!page) throw new Error('找不到可调试的页面，Edge 起来了吗？');

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });

  let seq = 0;
  const pending = new Map();
  ws.addEventListener('message', (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  });
  const send = (method, params) => new Promise((res) => {
    const id = ++seq;
    pending.set(id, res);
    ws.send(JSON.stringify({ id, method, params: params || {} }));
  });

  await send('Runtime.enable');
  await send('Page.enable');
  if (url && url !== '-') {
    await send('Page.navigate', { url });
    await sleep(4500);
  }
  const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
  const out = r.result && r.result.result ? r.result.result.value : r;
  console.log(typeof out === 'string' ? out : JSON.stringify(out, null, 2));
  ws.close();
}

main().catch((e) => { console.error('ERR', e.message); process.exit(1); });
