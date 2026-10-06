import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
const dir = process.argv[2];
const B = (await import(pathToFileURL(resolve(dir, 'B.js')).href)).default;
console.log(B['0'](41));
