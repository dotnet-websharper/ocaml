import { JSDOM } from 'jsdom';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const appDir = process.argv[2];
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
  url: 'http://localhost/',
  pretendToBeVisual: true
});
globalThis.window = dom.window;
globalThis.document = dom.window.document;

await import(pathToFileURL(resolve(appDir, 'Main.js')).href);

const { window } = dom;
const box = window.document.getElementById('box');
console.log('box present:', box !== null);
console.log('box className:', box ? box.className : '');
console.log('box text before:', box ? box.textContent : '');
box.dispatchEvent(new window.Event('ping'));
console.log('box text after:', box ? box.textContent : '');
