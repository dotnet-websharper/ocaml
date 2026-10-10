// Drives the native RPC server with structured payloads (records, variants,
// tuples, lists, options) in the OCaml runtime representation and prints the
// results. The wire format matches what the OCaml client's `rpcCall` sends.
const endpoint = 'http://127.0.0.1:8123/rpc';

const calls = [
  ['move', [{ $tag: 0, 0: 1, 1: 2 }]],
  ['area', [0]],
  ['area', [{ $tag: 1, 0: 5 }]],
  ['area', [{ $tag: 2, 0: { $tag: 0, 0: 0, 1: 0 }, 1: { $tag: 0, 0: 3, 1: 4 } }]],
  ['swap', [{ $tag: 0, 0: 7, 1: 'hi' }]],
  ['total', [{ $tag: 0, 0: 1, 1: { $tag: 0, 0: 2, 1: { $tag: 0, 0: 3, 1: 0 } } }]],
  ['or_else', [{ $tag: 0, 0: 5 }]],
  ['or_else', [0]],
  ['sum_tree', [{ $tag: 0, 0: 5 }]],
  ['sum_tree', [{ $tag: 1, 0: { $tag: 0, 0: 1 }, 1: { $tag: 0, 0: 2 } }]],
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
