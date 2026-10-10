// Drives a wsocaml sitelet server: fetches a server-rendered page, checks the
// SSR markup + injected scripts, calls an RPC, and fetches a static asset.
const base = 'http://127.0.0.1:8123';
const page = await (await fetch(base + '/')).text();
console.log('has-title:', page.includes('<title>Site</title>'));
console.log('has-ssr:', page.includes('server-rendered'));
console.log('has-scripts:', page.includes('<script type="module" src="/Main.js"></script>'));
const user = await (await fetch(base + '/user/5')).text();
console.log('user-ssr:', user.includes('User 5'));
const r = await fetch(base + '/rpc', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name: 'add', args: [20, 22] }),
});
console.log('rpc add(20,22):', (await r.json()).result);
const s = await fetch(base + '/Main.js');
console.log('static:', s.status, (s.headers.get('content-type') || '').split(';')[0].trim());
