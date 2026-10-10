// A plain (non-OCaml) JS consumer of the compiled OCaml library. Imports the
// [@export]ed API and passes JS-idiomatic values.
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
const mod = await import(pathToFileURL(resolve(dir, 'Main.js')).href);

console.log('label:', mod.label);
console.log('add:', mod.add(2, 3));
console.log('move:', JSON.stringify(mod.move({ x: 1, y: 2 })));
console.log('area Dot:', mod.area({ $: 'Dot' }));
console.log('area Circle:', mod.area({ $: 'Circle', $0: 5 }));
console.log('area Rect:', mod.area({ $: 'Rect', $0: { x: 0, y: 0 }, $1: { x: 3, y: 4 } }));
console.log('total:', mod.total([1, 2, 3]));
