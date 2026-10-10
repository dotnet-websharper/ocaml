import { JSDOM } from 'jsdom';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const clientDir = process.argv[2];
const page = await (await fetch('http://127.0.0.1:8123/')).text();
console.log('has-ssr-region:', page.includes('data-ws-key="Main.app"'));
console.log('has-ssr-content:', page.includes('server-rendered'));

const dom = new JSDOM(page, { url: 'http://localhost/', pretendToBeVisual: true });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame.bind(dom.window);
globalThis.cancelAnimationFrame = dom.window.cancelAnimationFrame.bind(dom.window);

const app = dom.window.document.getElementById('app');
console.log('ssr-content:', app.textContent);

await import(pathToFileURL(resolve(clientDir, 'Main.js')).href);
const n = globalThis.OCamlRuntime.hydrate();

setTimeout(() => {
  console.log('hydrated:', n);
  console.log('after-hydrate:', app.textContent);
  app.firstElementChild.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  setTimeout(() => {
    console.log('after-click:', app.textContent);
    process.exit(0);
  }, 50);
}, 50);
