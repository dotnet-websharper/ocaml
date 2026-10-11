// Verifies the hello-world sitelet: fetches the server-rendered page, checks the
// injected scripts, then hydrates the client-side piece in jsdom and clicks it.
import { JSDOM } from 'jsdom';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const out = process.argv[2] ?? 'out';
const base = 'http://127.0.0.1:8123';

const page = await (await fetch(base + '/')).text();
console.log('has-title:', page.includes('<title>Hello, world!</title>'));
console.log('has-hydrate:', page.includes('data-ws-key=') && page.includes('>before<'));
console.log('has-scripts:', page.includes('<script type="module" src="/Main.js"></script>'));
console.log('has-bootstrap:', page.includes('OCamlRuntime.hydrate()'));

const dom = new JSDOM(page, { url: 'http://localhost/', pretendToBeVisual: true });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame.bind(dom.window);
globalThis.cancelAnimationFrame = dom.window.cancelAnimationFrame.bind(dom.window);

await import(pathToFileURL(resolve(out, 'client', 'Main.js')).href);
const n = globalThis.OCamlRuntime.hydrate();
const region = dom.window.document.querySelector('[data-ws-key]');

setTimeout(() => {
  console.log('hydrated:', n > 0);
  console.log('before:', region.textContent);
  region.firstElementChild.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  setTimeout(() => {
    console.log('after:', region.textContent);
    process.exit(0);
  }, 50);
}, 50);
