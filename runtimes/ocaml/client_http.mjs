import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
await import(pathToFileURL(resolve(dir, 'Main.js')).href);

// Point the RPC transport at the native OCaml server and call over HTTP.
globalThis.OCamlRuntime.rpcEndpoint = 'http://127.0.0.1:8123/rpc';
const result = await globalThis.OCamlRuntime.rpcCall('g', [21]);
console.log('rpc g(21) =', result);
