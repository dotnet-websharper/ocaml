import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
const f = M['1'];
console.log(f(-5));
console.log(f(10));
