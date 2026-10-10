import { JSDOM } from 'jsdom';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const appDir = process.argv[2];
// A "server-rendered" page with a placeholder for the client region.
const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="app" data-ws-key="Main.app">loading…</div></body></html>',
  { url: 'http://localhost/', pretendToBeVisual: true }
);
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame.bind(dom.window);
globalThis.cancelAnimationFrame = dom.window.cancelAnimationFrame.bind(dom.window);

await import(pathToFileURL(resolve(appDir, 'Main.js')).href);

const app = dom.window.document.getElementById('app');
console.log('placeholder:', app.textContent);
const n = globalThis.OCamlRuntime.hydrate();

setTimeout(() => {
  console.log('hydrated:', n);
  console.log('before:', app.textContent);
  app.firstElementChild.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  setTimeout(() => {
    console.log('after:', app.textContent);
    process.exit(0);
  }, 50);
}, 50);
