import { pathToFileURL } from 'node:url';
const M = (await import(pathToFileURL(process.argv[2]).href)).default;
console.log(M['0']); // caml_compare [1;2] [1;3]  => -1
console.log(M['1']); // caml_equal   [1;2] [1;2]  => 1
console.log(M['2']); // caml_obj_tag (tag-1 block) => 1
console.log(M['3']); // Array.make 3 7 |> length   => 3
console.log(M['4'] === M['5']); // hash of equal blocks must match => true
