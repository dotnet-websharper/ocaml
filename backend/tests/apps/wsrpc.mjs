import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
// Load the server bundle first (registers the `[@rpc]` handlers), then the
// client, whose `rpcCall` proxies reach the handlers.
await import(pathToFileURL(resolve(dir, 'server', 'Main.js')).href);
await import(pathToFileURL(resolve(dir, 'Main.js')).href);
