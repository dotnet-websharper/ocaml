// Drives the native RPC server with structured payloads in the JS-idiomatic
// external representation (records -> objects, variants -> {"$":...,"$0":...},
// lists/arrays -> arrays, options -> value/null, tuples -> arrays), matching
// what the OCaml client marshals.
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const endpoint = 'http://127.0.0.1:8123/rpc';

const calls = [
  ['move', [{ x: 1, y: 2 }]],
  ['area', [{ $: 'Dot' }]],
  ['area', [{ $: 'Circle', $0: 5 }]],
  ['area', [{ $: 'Rect', $0: { x: 0, y: 0 }, $1: { x: 3, y: 4 } }]],
  ['swap', [[7, 'hi']]],
  ['total', [[1, 2, 3]]],
  ['or_else', [5]],
  ['or_else', [null]],
  ['sum_tree', [{ $: 'Leaf', $0: 5 }]],
  ['sum_tree', [{ $: 'Node', $0: { $: 'Leaf', $0: 1 }, $1: { $: 'Leaf', $0: 2 } }]],
  ['rev', [[1, 2, 3]]],
];

for (const [name, args] of calls) {
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, args }),
  });
  const json = await res.json();
  console.log(name + ' => ' + JSON.stringify(json.result));
}

// The same shapes through the *client* bundle's generated descriptors: import
// the server bundle first (installs the runtime prelude), point the transport at
// the native server, then import the client bundle, whose `let () =` chains the
// calls. Node keeps the process alive until those fetches settle, so the lines
// land after `f=42` without any timer.
if (process.argv[2]) {
  const dir = process.argv[2];
  await import(pathToFileURL(resolve(dir, 'Main.server.js')).href);
  globalThis.OCamlRuntime.rpcEndpoint = endpoint;
  await import(pathToFileURL(resolve(dir, 'Main.js')).href);
}
