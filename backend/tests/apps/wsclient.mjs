import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const dir = process.argv[2];
await import(pathToFileURL(resolve(dir, 'Main.js')).href);

// The `client` closure must have been emitted as a standalone client unit.
const unit = await import(pathToFileURL(resolve(dir, 'clientserver', 'client0.js')).href);
console.log('client0:', typeof unit.default);
