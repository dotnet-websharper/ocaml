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

await import(pathToFileURL(resolve(appDir, 'Main.js')).href);

console.log('root:', dom.window.document.getElementById('root').textContent);
