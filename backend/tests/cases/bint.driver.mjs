import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
console.log(String(M['0'])); // 5L + 7L        => 12
console.log(String(M['1'])); // 1000000000000L * 3L => 3000000000000
console.log(M['2']); // 2000000000l + 2000000000l (int32 wrap) => -294967296
console.log(M['3']); // Int32.of_int 42 => 42
console.log(String(M['4'])); // 1L << 40 => 1099511627776
console.log(M['5']); // 5L > 3L => 1
