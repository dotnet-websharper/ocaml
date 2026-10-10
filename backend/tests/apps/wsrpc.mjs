import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
const client = readFileSync(resolve(dir, 'Main.js'), 'utf8');
console.log('client-has-proxy:', client.includes('rpcCall("g"'));

// Server registers the handler; client runs (prints f=42); then drive both the
// raw runtime call and OCaml-side `Async.bind` (via the module's `bump`).
await import(pathToFileURL(resolve(dir, 'Main.server.js')).href);
const Main = (await import(pathToFileURL(resolve(dir, 'Main.js')).href)).default;
const result = await globalThis.OCamlRuntime.rpcCall('g', [21]);
console.log('rpc g(21) =', result);
const bump = Main[2];
console.log('Async.bind g(20)+1 =', await bump(20));
