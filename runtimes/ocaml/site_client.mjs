// Drives a wsocaml sitelet server: fetches server-rendered pages, checks SSR
// markup + injected scripts, hydrates a client region in jsdom, calls an RPC,
// and fetches a static asset.
import { JSDOM } from 'jsdom';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const base = 'http://127.0.0.1:8123';
const clientDir = process.argv[2];

const page = await (await fetch(base + '/')).text();
console.log('has-title:', page.includes('<title>Site</title>'));
console.log('has-ssr:', page.includes('server-rendered'));
console.log('has-hydrate:', page.includes('data-ws-key=') && page.includes('>before<'));
console.log('has-scripts:', page.includes('<script type="module" src="/Main.js"></script>'));
console.log('has-bootstrap:', page.includes('OCamlRuntime.hydrate()'));
const user = await (await fetch(base + '/user/5')).text();
console.log('user-ssr:', user.includes('User 5'));

const dom = new JSDOM(page, { url: 'http://localhost/', pretendToBeVisual: true });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame.bind(dom.window);
globalThis.cancelAnimationFrame = dom.window.cancelAnimationFrame.bind(dom.window);

await import(pathToFileURL(resolve(clientDir, 'Main.js')).href);
const n = globalThis.OCamlRuntime.hydrate();
const region = dom.window.document.querySelector('[data-ws-key]');

setTimeout(async () => {
  console.log('hydrated:', n > 0);
  console.log('before:', region.textContent);
  region.firstElementChild.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  setTimeout(async () => {
    console.log('after:', region.textContent);
    const r = await fetch(base + '/rpc', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'add', args: [20, 22] }),
    });
    console.log('rpc add(20,22):', (await r.json()).result);
    const s = await fetch(base + '/Main.js');
    console.log('static:', s.status, (s.headers.get('content-type') || '').split(';')[0].trim());
    process.exit(0);
  }, 50);
}, 50);
