import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
const area = M['0'];
const classify = M['1'];
const factorial = M['2'];
console.log(area({ $tag: 0, '0': 2.0 }));
console.log(area({ $tag: 1, '0': 3.0, '1': 4.0 }));
console.log(classify(0), classify(1), classify(5));
console.log(factorial(5));
