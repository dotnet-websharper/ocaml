import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
console.log(M['0']); // force (lazy (40+2)) => 42
console.log(M['1']); // force again (cached)  => 42
console.log(M['2']); // force (make_forward 99) => 99
console.log(M['3']); // force of a non-lazy value => 5
