import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
await import(pathToFileURL(resolve(dir, 'Main.js')).href);

// The captured environment registered by the entry.
const env = globalThis.OCamlRuntime.__clients.client0;
console.log('captured-base:', env.base);

// The client unit is a factory that reconstructs the closure from an env.
const factory = (await import(pathToFileURL(resolve(dir, 'clientserver', 'client0.js')).href)).default;
console.log('factory(100)(1):', factory({ base: 100 })(1));
