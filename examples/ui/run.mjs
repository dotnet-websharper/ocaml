import { JSDOM } from 'jsdom';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const appDir = process.argv[2] ?? '_build/default/out';
const dom = new JSDOM('<!DOCTYPE html><html><body><div id="root"></div></body></html>', {
  url: 'http://localhost/',
  pretendToBeVisual: true
});
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame.bind(dom.window);
globalThis.cancelAnimationFrame = dom.window.cancelAnimationFrame.bind(dom.window);

await import(pathToFileURL(resolve(appDir, 'Main.js')).href);

setTimeout(() => {
  const root = dom.window.document.getElementById('root');
  console.log('root:', root.textContent);
  console.log('html:', root.innerHTML);
  process.exit(0);
}, 50);
