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
window.dispatchEvent(new window.MouseEvent('click', { clientX: 10, clientY: 20 }));
window.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'A' }));
window.document.getElementById('box').dispatchEvent(new window.Event('ping'));
const box = window.document.getElementById('box');
console.log('box present:', box !== null);
console.log('box text:', box ? box.textContent : '');
console.log('input value:', window.document.querySelector('input').value);
console.log('option value:', window.document.querySelector('option').value);
console.log('localStorage k:', window.localStorage.getItem('k'));
