import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
console.log(M['0']); // Bytes "Hi!" -> "Hi!"
console.log(M['1']); // String.get "AB" 1 -> 66
