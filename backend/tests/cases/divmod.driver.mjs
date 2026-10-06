import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
console.log(M['0']); // 7 / 2   => 3
console.log(M['1']); // -7 / 2  => -3
console.log(M['2']); // 7 mod 2 => 1
console.log(M['3']); // -7 mod 2 => -1
