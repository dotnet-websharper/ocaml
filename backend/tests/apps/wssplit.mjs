import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
const client = readFileSync(resolve(dir, 'Main.js'), 'utf8');
const server = readFileSync(resolve(dir, 'Main.server.js'), 'utf8');
console.log('client-has-secret:', client.includes('777777'));
console.log('server-has-secret:', server.includes('777777'));

// Server registers the rpc handlers, then the client runs and calls `g`.
await import(pathToFileURL(resolve(dir, 'Main.server.js')).href);
await import(pathToFileURL(resolve(dir, 'Main.js')).href);
