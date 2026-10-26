import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

// Typed JSON: `wsjson.ml`'s `let () =` encodes, decodes and re-encodes a
// structured value. No DOM/runtime prelude beyond `Main.js` itself is needed.
const dir = process.argv[2];
await import(pathToFileURL(resolve(dir, 'Main.js')).href);
