import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
const client = readFileSync(resolve(dir, 'Main.js'), 'utf8');
console.log('client-has-proxy:', client.includes('rpcCall("g"'));

// Server registers the handler; client runs (prints f=42); then drive the
// asynchronous, serialized RPC through the runtime.
await import(pathToFileURL(resolve(dir, 'Main.server.js')).href);
await import(pathToFileURL(resolve(dir, 'Main.js')).href);
const result = await globalThis.OCamlRuntime.rpcCall('g', [21]);
console.log('rpc g(21) =', result);
