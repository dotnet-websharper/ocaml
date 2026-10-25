import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

// Drives the *generated* `[@rpc]` proxies for structured payloads. The server
// bundle (same source, server side = `[@rpc]` bodies kept) installs the runtime
// prelude and registers the in-process handlers; importing the client bundle
// then runs `wsdata.ml`'s `let () =`, which round-trips records, variants,
// tuples, lists, options and arrays through the generated type descriptor and
// the runtime marshaller (`scripts/rpc-data.sh` additionally drives the same
// proxies over HTTP against the *native* server, so the native codecs are on
// the other side of the wire there).
const dir = process.argv[2];
await import(pathToFileURL(resolve(dir, 'Main.server.js')).href);
await import(pathToFileURL(resolve(dir, 'Main.js')).href);
