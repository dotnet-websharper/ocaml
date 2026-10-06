import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
console.log(M['0'](20, 22));
console.log(M['1'](6));
console.log(M['2']);
