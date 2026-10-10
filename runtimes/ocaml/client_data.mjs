// Drives the native RPC server with structured payloads in the JS-idiomatic
// external representation (records -> objects, variants -> {"$":...,"$0":...},
// lists/arrays -> arrays, options -> value/null, tuples -> arrays), matching
// what the OCaml client marshals.
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
