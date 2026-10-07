#!/usr/bin/env python3
"""Generate a `.js` shim for an OCaml stdlib unit from its module-block layout.

Each stdlib unit (`Stdlib`, `Stdlib__Array`, `Stdlib__String`, ...) is a normal
module block addressed by field index. We read `ocamlobjinfo <unit>.cmx`
(Clambda approximation) to recover the index -> value mapping, then emit a JS
module whose numeric fields are filled with runtime-backed implementations for
the names we support, constants, or a throwing stub.

Usage: gen-stdlib-shim.py <output.js> [Unit]
       (Unit defaults to Stdlib; file must be <unit>.cmx or stdlib__<unit>.cmx)
"""
import re
import subprocess
import sys

# ---- per-unit implementations (name -> JS, arity matches the OCaml value) ----

STDLIB = {
    "print_char": "(c) => { out(String.fromCharCode(c)); return 0; }",
    "print_string": "(x) => { out(String(x)); return 0; }",
    "print_bytes": "(x) => { out(String(x)); return 0; }",
    "print_int": "(n) => { out(String(n)); return 0; }",
    "print_float": "(f) => { out(String(f)); return 0; }",
    "print_endline": "(x) => { out(String(x) + '\\n'); return 0; }",
    "print_newline": "() => { out('\\n'); return 0; }",
    "prerr_char": "(c) => { out(String.fromCharCode(c)); return 0; }",
    "prerr_string": "(x) => { out(String(x)); return 0; }",
    "prerr_bytes": "(x) => { out(String(x)); return 0; }",
    "prerr_int": "(n) => { out(String(n)); return 0; }",
    "prerr_float": "(f) => { out(String(f)); return 0; }",
    "prerr_endline": "(x) => { out(String(x) + '\\n'); return 0; }",
    "prerr_newline": "() => { out('\\n'); return 0; }",
    "string_of_int": "(n) => String(n)",
    "string_of_bool": "(b) => (b ? 'true' : 'false')",
    "string_of_float": "(f) => String(f)",
    "char_of_int": "(n) => n",
    "int_of_string": "(s) => { const n = parseInt(s, 10); if (isNaN(n)) throw new Error('int_of_string'); return n; }",
    "float_of_string": "(s) => { const n = parseFloat(s); if (isNaN(n)) throw new Error('float_of_string'); return n; }",
    "min": "(a, b) => (a < b ? a : b)",
    "max": "(a, b) => (a > b ? a : b)",
    "abs": "(a) => Math.abs(a)",
    "lnot": "(a) => ~a",
    "failwith": "(s) => { throw new Error(String(s)); }",
    "invalid_arg": "(s) => { throw new Error(String(s)); }",
    "at_exit": "(f) => 0",
    "exit": "(n) => { throw new Error('exit ' + String(n)); }",
    "bool_of_string_opt": "(s) => (s === 'true' ? { $tag: 0, '0': 1 } : (s === 'false' ? { $tag: 0, '0': 0 } : 0))",
    "int_of_string_opt": "(s) => { const n = parseInt(s, 10); return isNaN(n) ? 0 : { $tag: 0, '0': n }; }",
    "float_of_string_opt": "(s) => { const n = parseFloat(s); return isNaN(n) ? 0 : { $tag: 0, '0': n }; }",
    "flush_all": "() => 0",
    "do_at_exit": "() => 0",
    "valid_float_lexem": "(s) => s",
    "output_string": "(ch, s) => { out(String(s)); return 0; }",
    "output_bytes": "(ch, b) => { for (var i = 0; i < b.length; i++) out(String.fromCharCode(b[i])); return 0; }",
    "output": "(ch, s, ofs, len) => { out(String(s).substr(ofs, len)); return 0; }",
    "output_substring": "(ch, s, ofs, len) => { out(String(s).substr(ofs, len)); return 0; }",
    "close_out": "(ch) => 0",
    "close_out_noerr": "(ch) => 0",
    "open_out": "(fn) => 0",
    "open_out_bin": "(fn) => 0",
    "open_out_gen": "(m, p, fn) => 0",
    "^": "(a, b) => String(a) + String(b)",
    "@": "(a, b) => { const s = []; let l = a; while (l !== 0) { s.push(l['0']); l = l['1']; } let r = b; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
}

ARRAY = {
    "length": "(a) => a.length",
    "get": "(a, i) => a[i]",
    "set": "(a, i, v) => { a[i] = v; return 0; }",
    "init": "(n, f) => { const a = new Array(n); for (let i = 0; i < n; i++) a[i] = ap(f, [i]); return a; }",
    "append": "(a, b) => a.concat(b)",
    "sub": "(a, ofs, len) => a.slice(ofs, ofs + len)",
    "copy": "(a) => a.slice()",
    "fill": "(a, ofs, len, v) => { for (let i = 0; i < len; i++) a[ofs + i] = v; return 0; }",
    "blit": "(a1, o1, a2, o2, len) => { for (let i = 0; i < len; i++) a2[o2 + i] = a1[o1 + i]; return 0; }",
    "map": "(f, a) => a.map((x) => ap(f, [x]))",
    "mapi": "(f, a) => a.map((x, i) => ap(f, [i, x]))",
    "iter": "(f, a) => { a.forEach((x) => ap(f, [x])); return 0; }",
    "iteri": "(f, a) => { a.forEach((x, i) => ap(f, [i, x])); return 0; }",
    "fold_left": "(f, init, a) => { let acc = init; for (let i = 0; i < a.length; i++) acc = ap(f, [acc, a[i]]); return acc; }",
    "fold_right": "(f, a, init) => { let acc = init; for (let i = a.length - 1; i >= 0; i--) acc = ap(f, [a[i], acc]); return acc; }",
    "to_list": "(a) => { let l = 0; for (let i = a.length - 1; i >= 0; i--) l = { $tag: 0, '0': a[i], '1': l }; return l; }",
    "of_list": "(l) => { const a = []; while (l !== 0) { a.push(l['0']); l = l['1']; } return a; }",
    "mem": "(x, a) => (a.some((v) => v === x) ? 1 : 0)",
    "memq": "(x, a) => (a.some((v) => v === x) ? 1 : 0)",
    "for_all": "(f, a) => (a.every((x) => ap(f, [x])) ? 1 : 0)",
    "exists": "(f, a) => (a.some((x) => ap(f, [x])) ? 1 : 0)",
    "find_opt": "(f, a) => { const i = a.findIndex((x) => ap(f, [x])); return i < 0 ? 0 : { $tag: 0, '0': a[i] }; }",
    "combine": "(a, b) => a.map((x, i) => ({ $tag: 0, '0': x, '1': b[i] }))",
    "sort": "(cmp, a) => { a.sort((x, y) => ap(cmp, [x, y])); return 0; }",
    "stable_sort": "(cmp, a) => { a.sort((x, y) => ap(cmp, [x, y])); return 0; }",
}

STRING = {
    "length": "(s) => s.length",
    "get": "(s, i) => s.charCodeAt(i)",
    "make": "(n, c) => String.fromCharCode(c).repeat(n)",
    "create": "(n) => '\\0'.repeat(n)",
    "sub": "(s, ofs, len) => s.substr(ofs, len)",
    "blit": "(s1, o1, s2, o2, len) => { throw new Error('String.blit unsupported'); }",
    "concat": "(sep, list) => { const a = []; let l = list; while (l !== 0) { a.push(l['0']); l = l['1']; } return a.join(sep); }",
    "iter": "(f, s) => { for (let i = 0; i < s.length; i++) ap(f, [s.charCodeAt(i)]); return 0; }",
    "iteri": "(f, s) => { for (let i = 0; i < s.length; i++) ap(f, [i, s.charCodeAt(i)]); return 0; }",
    "map": "(f, s) => { let r = ''; for (let i = 0; i < s.length; i++) r += String.fromCharCode(ap(f, [s.charCodeAt(i)])); return r; }",
    "mapi": "(f, s) => { let r = ''; for (let i = 0; i < s.length; i++) r += String.fromCharCode(ap(f, [i, s.charCodeAt(i)])); return r; }",
    "uppercase_ascii": "(s) => s.toUpperCase()",
    "lowercase_ascii": "(s) => s.toLowerCase()",
    "compare": "(a, b) => (a < b ? -1 : a > b ? 1 : 0)",
    "equal": "(a, b) => (a === b ? 1 : 0)",
    "copy": "(s) => s",
    "trim": "(s) => s.trim()",
    "split_on_char": "(sep, s) => { const parts = s.split(String.fromCharCode(sep)); let l = 0; for (let i = parts.length - 1; i >= 0; i--) l = { $tag: 0, '0': parts[i], '1': l }; return l; }",
    "to_string": "(s) => s",
    "contains": "(s, c) => (s.indexOf(String.fromCharCode(c)) >= 0 ? 1 : 0)",
    "starts_with": "(prefix, s) => (s.startsWith(prefix) ? 1 : 0)",
    "ends_with": "(suffix, s) => (s.endsWith(suffix) ? 1 : 0)",
    "index_opt": "(s, c) => { const i = s.indexOf(String.fromCharCode(c)); return i < 0 ? 0 : { $tag: 0, '0': i }; }",
    "for_all": "(f, s) => { for (let i = 0; i < s.length; i++) if (!ap(f, [s.charCodeAt(i)])) return 0; return 1; }",
    "exists": "(f, s) => { for (let i = 0; i < s.length; i++) if (ap(f, [s.charCodeAt(i)])) return 1; return 0; }",
    "fold_left": "(f, acc, s) => { for (let i = 0; i < s.length; i++) acc = ap(f, [acc, s.charCodeAt(i)]); return acc; }",
    "fold_right": "(f, s, acc) => { for (let i = s.length - 1; i >= 0; i--) acc = ap(f, [s.charCodeAt(i), acc]); return acc; }",
    "init": "(n, f) => { let r = ''; for (let i = 0; i < n; i++) r += String.fromCharCode(ap(f, [i])); return r; }",
    "capitalize_ascii": "(s) => (s.length ? s[0].toUpperCase() + s.slice(1) : s)",
    "uncapitalize_ascii": "(s) => (s.length ? s[0].toLowerCase() + s.slice(1) : s)",
}

LIST = {
    "length": "(l) => { let n = 0; while (l !== 0) { n++; l = l['1']; } return n; }",
    "hd": "(l) => l['0']",
    "tl": "(l) => l['1']",
    "cons": "(x, l) => ({ $tag: 0, '0': x, '1': l })",
    "singleton": "(x) => ({ $tag: 0, '0': x, '1': 0 })",
    "is_empty": "(l) => (l === 0 ? 1 : 0)",
    "rev": "(l) => { let r = 0; while (l !== 0) { r = { $tag: 0, '0': l['0'], '1': r }; l = l['1']; } return r; }",
    "rev_append": "(l1, l2) => { while (l1 !== 0) { l2 = { $tag: 0, '0': l1['0'], '1': l2 }; l1 = l1['1']; } return l2; }",
    "append": "(l1, l2) => { const s = []; while (l1 !== 0) { s.push(l1['0']); l1 = l1['1']; } let r = l2; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "map": "(f, l) => { const s = []; while (l !== 0) { s.push(ap(f, [l['0']])); l = l['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "iter": "(f, l) => { while (l !== 0) { ap(f, [l['0']]); l = l['1']; } return 0; }",
    "iteri": "(f, l) => { let i = 0; while (l !== 0) { ap(f, [i, l['0']]); i++; l = l['1']; } return 0; }",
    "fold_left": "(f, acc, l) => { while (l !== 0) { acc = ap(f, [acc, l['0']]); l = l['1']; } return acc; }",
    "fold_right": "(f, l, acc) => { const s = []; while (l !== 0) { s.push(l['0']); l = l['1']; } for (let i = s.length - 1; i >= 0; i--) acc = ap(f, [s[i], acc]); return acc; }",
    "filter": "(f, l) => { const s = []; while (l !== 0) { if (ap(f, [l['0']])) s.push(l['0']); l = l['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "find_all": "(f, l) => { const s = []; while (l !== 0) { if (ap(f, [l['0']])) s.push(l['0']); l = l['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "nth": "(l, n) => { while (n > 0) { l = l['1']; n--; } return l['0']; }",
    "mem": "(x, l) => { while (l !== 0) { if (x === l['0']) return 1; l = l['1']; } return 0; }",
    "nth_opt": "(l, n) => { while (n > 0) { if (l === 0) return 0; l = l['1']; n--; } return l === 0 ? 0 : { $tag: 0, '0': l['0'] }; }",
    "find": "(f, l) => { while (l !== 0) { if (ap(f, [l['0']])) return l['0']; l = l['1']; } throw new Error('Not_found'); }",
    "find_opt": "(f, l) => { while (l !== 0) { if (ap(f, [l['0']])) return { $tag: 0, '0': l['0'] }; l = l['1']; } return 0; }",
    "for_all": "(f, l) => { while (l !== 0) { if (!ap(f, [l['0']])) return 0; l = l['1']; } return 1; }",
    "exists": "(f, l) => { while (l !== 0) { if (ap(f, [l['0']])) return 1; l = l['1']; } return 0; }",
    "concat": "(ll) => { const s = []; while (ll !== 0) { let l = ll['0']; while (l !== 0) { s.push(l['0']); l = l['1']; } ll = ll['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "flatten": "(ll) => { const s = []; while (ll !== 0) { let l = ll['0']; while (l !== 0) { s.push(l['0']); l = l['1']; } ll = ll['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "assoc": "(k, l) => { while (l !== 0) { const p = l['0']; if (p['0'] === k) return p['1']; l = l['1']; } throw new Error('Not_found'); }",
    "assoc_opt": "(k, l) => { while (l !== 0) { const p = l['0']; if (p['0'] === k) return { $tag: 0, '0': p['1'] }; l = l['1']; } return 0; }",
    "mem_assoc": "(k, l) => { while (l !== 0) { if (l['0']['0'] === k) return 1; l = l['1']; } return 0; }",
    "remove_assoc": "(k, l) => { const s = []; while (l !== 0) { if (l['0']['0'] !== k) s.push(l['0']); l = l['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "filter_map": "(f, l) => { const s = []; while (l !== 0) { const o = ap(f, [l['0']]); if (o !== 0) s.push(o['0']); l = l['1']; } let r = 0; for (let i = s.length - 1; i >= 0; i--) r = { $tag: 0, '0': s[i], '1': r }; return r; }",
    "rev_map": "(f, l) => { let r = 0; while (l !== 0) { r = { $tag: 0, '0': ap(f, [l['0']]), '1': r }; l = l['1']; } return r; }",
}

BYTES = {
    "length": "(b) => b.length",
    "get": "(b, i) => b[i]",
    "set": "(b, i, c) => { b[i] = c & 0xff; return 0; }",
    "make": "(n, c) => { const b = new Uint8Array(n); b.fill(c & 0xff); return b; }",
    "create": "(n) => new Uint8Array(n)",
    "of_string": "(s) => { const b = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) b[i] = s.charCodeAt(i); return b; }",
    "to_string": "(b) => { let s = ''; for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]); return s; }",
    "sub": "(b, ofs, len) => b.slice(ofs, ofs + len)",
    "copy": "(b) => b.slice()",
    "blit": "(b1, o1, b2, o2, len) => { for (let i = 0; i < len; i++) b2[o2 + i] = b1[o1 + i]; return 0; }",
    "fill": "(b, ofs, len, c) => { for (let i = 0; i < len; i++) b[ofs + i] = c; return 0; }",
    "compare": "(a, b) => { for (let i = 0; i < a.length && i < b.length; i++) { if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1; } return a.length - b.length; }",
    "equal": "(a, b) => { if (a.length !== b.length) return 0; for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return 0; return 1; }",
    "iter": "(f, b) => { for (let i = 0; i < b.length; i++) ap(f, [b[i]]); return 0; }",
    "iteri": "(f, b) => { for (let i = 0; i < b.length; i++) ap(f, [i, b[i]]); return 0; }",
    "map": "(f, b) => { const r = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) r[i] = ap(f, [b[i]]); return r; }",
    "mapi": "(f, b) => { const r = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) r[i] = ap(f, [i, b[i]]); return r; }",
    "fold_left": "(f, acc, b) => { for (let i = 0; i < b.length; i++) acc = ap(f, [acc, b[i]]); return acc; }",
    "fold_right": "(f, b, acc) => { for (let i = b.length - 1; i >= 0; i--) acc = ap(f, [b[i], acc]); return acc; }",
    "uppercase_ascii": "(b) => Uint8Array.from(b, (c) => (c >= 97 && c <= 122 ? c - 32 : c))",
    "lowercase_ascii": "(b) => Uint8Array.from(b, (c) => (c >= 65 && c <= 90 ? c + 32 : c))",
    "capitalize_ascii": "(b) => { const r = b.slice(); if (r.length && r[0] >= 97 && r[0] <= 122) r[0] -= 32; return r; }",
    "contains": "(b, c) => { for (let i = 0; i < b.length; i++) if (b[i] === c) return 1; return 0; }",
    "index_opt": "(b, c) => { for (let i = 0; i < b.length; i++) if (b[i] === c) return { $tag: 0, '0': i }; return 0; }",
}

HASHTBL = {
    "create": "() => new Map()",
    "add": "(t, k, v) => { t.set(k, v); return 0; }",
    "replace": "(t, k, v) => { t.set(k, v); return 0; }",
    "find": "(t, k) => { if (!t.has(k)) throw new Error('Not_found'); return t.get(k); }",
    "find_opt": "(t, k) => (t.has(k) ? { $tag: 0, '0': t.get(k) } : 0)",
    "mem": "(t, k) => (t.has(k) ? 1 : 0)",
    "remove": "(t, k) => { t.delete(k); return 0; }",
    "length": "(t) => t.size",
    "clear": "(t) => { t.clear(); return 0; }",
    "reset": "(t) => { t.clear(); return 0; }",
    "copy": "(t) => new Map(t)",
    "iter": "(f, t) => { t.forEach((v, k) => ap(f, [k, v])); return 0; }",
    "fold": "(f, t, acc) => { let a = acc; t.forEach((v, k) => { a = ap(f, [k, v, a]); }); return a; }",
    "hash": "(x) => (globalThis.OCamlRuntime ? globalThis.OCamlRuntime.caml_hash(x) : 0)",
    "seeded_hash": "(seed, x) => (globalThis.OCamlRuntime ? globalThis.OCamlRuntime.caml_hash(x) : 0)",
}

BUFFER = {
    "create": "() => []",
    "add_char": "(b, c) => { b.push(c); return 0; }",
    "add_string": "(b, s) => { for (let i = 0; i < s.length; i++) b.push(s.charCodeAt(i)); return 0; }",
    "add_bytes": "(b, bs) => { for (let i = 0; i < bs.length; i++) b.push(bs[i]); return 0; }",
    "add_substring": "(b, s, ofs, len) => { for (let i = 0; i < len; i++) b.push(s.charCodeAt(ofs + i)); return 0; }",
    "contents": "(b) => { let s = ''; for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]); return s; }",
    "length": "(b) => b.length",
    "clear": "(b) => { b.length = 0; return 0; }",
    "reset": "(b) => { b.length = 0; return 0; }",
    "nth": "(b, i) => b[i]",
    "truncate": "(b, n) => { b.length = n; return 0; }",
    "to_bytes": "(b) => Uint8Array.from(b)",
}

PRINTF_HELPERS = r'''
function feed(cont, rest) {
  while (rest.length && typeof cont === "function") cont = cont(rest.shift());
  return cont;
}
function pstr(a) { return (a === null || a === undefined) ? "" : String(a); }
function pquote(s) {
  var r = '"';
  for (var i = 0; i < s.length; i++) {
    var c = s.charCodeAt(i);
    if (c === 34) r += '\\"';
    else if (c === 92) r += '\\\\';
    else if (c === 10) r += '\\n';
    else if (c === 9) r += '\\t';
    else if (c < 32 || c > 126) r += '\\' + (c < 10 ? '00' : c < 100 ? '0' : '') + c;
    else r += s[i];
  }
  return r + '"';
}
function ppad(s, padding) {
  if (typeof padding !== "object") return s;
  if (padding.$tag === 0) {
    var padty = padding["0"], n = padding["1"];
    if (s.length >= n) return s;
    var fill = padty === 2 ? "0" : " ";
    var p = fill.repeat(n - s.length);
    return padty === 0 ? s + p : p + s;
  }
  return s;
}
function pprec(prec) { return (typeof prec === "object" && prec.$tag === 0) ? prec["0"] : -1; }
function pint(a, conv, padding, prec) {
  var n = a | 0, neg = n < 0, u = neg ? -n : n, base = 10, upper = false;
  if (conv === 6 || conv === 7) base = 16;
  else if (conv === 8 || conv === 9) { base = 16; upper = true; }
  else if (conv === 10 || conv === 11) base = 8;
  var s = u.toString(base);
  if (upper) s = s.toUpperCase();
  var md = pprec(prec);
  if (md > 0) { while (s.length < md) s = "0" + s; }
  var sign = neg ? "-" : ((conv === 1 || conv === 4 || conv === 14) ? "+" : ((conv === 2 || conv === 5) ? " " : ""));
  var prefix = conv === 7 ? "0x" : conv === 9 ? "0X" : conv === 11 ? "0o" : "";
  return ppad(sign + prefix + s, padding);
}
function pbig(a, conv, padding, prec) {
  var v = (typeof a === "bigint") ? a : BigInt(Math.trunc(a));
  var neg = v < 0n, u = neg ? -v : v, base = 10n;
  if (conv === 6 || conv === 7 || conv === 8 || conv === 9) base = 16n;
  else if (conv === 10 || conv === 11) base = 8n;
  var s = u.toString(Number(base));
  if (conv === 8 || conv === 9) s = s.toUpperCase();
  return ppad((neg ? "-" : "") + s, padding);
}
function pfloat(a, conv, padding, prec) {
  var flag = (typeof conv === "object") ? conv["0"] : 0;
  var kind = (typeof conv === "object") ? conv["1"] : 0;
  var p = pprec(prec);
  if (p < 0) p = 6;
  var s;
  if (kind === 1 || kind === 2) s = a.toExponential(p);
  else if (kind === 3 || kind === 4) { s = a.toPrecision(p + 1); if (s.indexOf("e") < 0 && s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, ""); }
  else s = a.toFixed(p);
  if (kind === 2 || kind === 4) s = s.toUpperCase();
  if (flag === 1 && a >= 0) s = "+" + s;
  else if (flag === 2 && a >= 0) s = " " + s;
  return ppad(s, padding);
}
function plit(l) {
  if (typeof l !== "object") {
    if (l === 3 || l === 4) return "\n";
    if (l === 5) return "@";
    if (l === 6) return "%";
    return "";
  }
  if (l.$tag === 0) return l["0"];
  if (l.$tag === 2) return String.fromCharCode(l["0"]);
  return "";
}
function pwalk(fmt, emit, done) {
  if (typeof fmt !== "object") return done();
  var tag = fmt.$tag;
  switch (tag) {
    case 11: emit(fmt["0"]); return pwalk(fmt["1"], emit, done);
    case 12: emit(String.fromCharCode(fmt["0"])); return pwalk(fmt["1"], emit, done);
    case 0: return function (a) { emit(String.fromCharCode(a)); return pwalk(fmt["0"], emit, done); };
    case 1: return function (a) { emit(String.fromCharCode(a)); return pwalk(fmt["0"], emit, done); };
    case 2: return function (a) { emit(ppad(pstr(a), fmt["0"])); return pwalk(fmt["1"], emit, done); };
    case 3: return function (a) { emit(ppad(pquote(pstr(a)), fmt["0"])); return pwalk(fmt["1"], emit, done); };
    case 4: case 5: return function (a) { emit(pint(a, fmt["0"], fmt["1"], fmt["2"])); return pwalk(fmt["3"], emit, done); };
    case 6: case 7: return function (a) { emit(pbig(a, fmt["0"], fmt["1"], fmt["2"])); return pwalk(fmt["3"], emit, done); };
    case 8: return function (a) { emit(pfloat(a, fmt["0"], fmt["1"], fmt["2"])); return pwalk(fmt["3"], emit, done); };
    case 9: return function (a) { emit(a ? "true" : "false"); return pwalk(fmt["1"], emit, done); };
    case 10: return pwalk(fmt["0"], emit, done);
    case 17: emit(plit(fmt["0"])); return pwalk(fmt["1"], emit, done);
    case 18: return pwalk(fmt["1"], emit, done);
    case 15: return function (f) { return function (x) { ap(f, [0, x]); return pwalk(fmt["0"], emit, done); }; };
    case 16: return function (f) { ap(f, [0]); return pwalk(fmt["0"], emit, done); };
    default: throw new Error("Printf: unsupported directive tag " + tag);
  }
}
'''.strip().split("\n")

PRINTF = {
    "printf": "function (fmt) { var emit = function (s) { out(s); return 0; }; return feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 1)); }",
    "eprintf": "function (fmt) { var emit = function (s) { out(s); return 0; }; return feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 1)); }",
    "sprintf": "function (fmt) { var buf = ''; var emit = function (s) { buf += s; return 0; }; return feed(pwalk(fmt['0'], emit, function () { return buf; }), Array.prototype.slice.call(arguments, 1)); }",
    "fprintf": "function (ch, fmt) { var emit = function (s) { out(s); return 0; }; return feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 2)); }",
    "ksprintf": "function (k, fmt) { var buf = ''; var emit = function (s) { buf += s; return 0; }; feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 2)); return ap(k, [buf]); }",
    "ifprintf": "function (fmt) { feed(pwalk(fmt['0'], function () { return 0; }, function () { return 0; }), Array.prototype.slice.call(arguments, 1)); return 0; }",
    "kfprintf": "function (k, ch, fmt) { var emit = function (s) { out(s); return 0; }; feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 3)); return ap(k, [ch]); }",
    "ikfprintf": "function (k, fmt) { feed(pwalk(fmt['0'], function () { return 0; }, function () { return 0; }), Array.prototype.slice.call(arguments, 2)); return ap(k, [0]); }",
    "bprintf": "function (buf, fmt) { var emit = function (s) { for (var i = 0; i < s.length; i++) buf.push(s.charCodeAt(i)); return 0; }; return feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 2)); }",
    "kbprintf": "function (k, buf, fmt) { var emit = function (s) { for (var i = 0; i < s.length; i++) buf.push(s.charCodeAt(i)); return 0; }; feed(pwalk(fmt['0'], emit, function () { return 0; }), Array.prototype.slice.call(arguments, 3)); return ap(k, [buf]); }",
}

OPTION = {
    "some": "(x) => ({ $tag: 0, '0': x })",
    "is_some": "(o) => (o !== 0 ? 1 : 0)",
    "is_none": "(o) => (o === 0 ? 1 : 0)",
    "get": "(o) => { if (o === 0) throw new Error('Option.get'); return o['0']; }",
    "value": "(o, d) => (o === 0 ? d : o['0'])",
    "map": "(f, o) => (o === 0 ? 0 : { $tag: 0, '0': ap(f, [o['0']]) })",
    "bind": "(o, f) => (o === 0 ? 0 : ap(f, [o['0']]))",
    "iter": "(f, o) => { if (o !== 0) ap(f, [o['0']]); return 0; }",
    "fold": "(none_, some_, o) => (o === 0 ? none_ : ap(some_, [o['0']]))",
    "join": "(oo) => (oo === 0 ? 0 : oo['0'])",
    "to_list": "(o) => (o === 0 ? 0 : { $tag: 0, '0': o['0'], '1': 0 })",
    "to_result": "(none_, o) => (o === 0 ? { $tag: 1, '0': none_ } : { $tag: 0, '0': o['0'] })",
    "equal": "(eq, a, b) => (a === 0 ? (b === 0 ? 1 : 0) : (b === 0 ? 0 : ap(eq, [a['0'], b['0']])))",
    "compare": "(cmp, a, b) => (a === 0 ? (b === 0 ? 0 : -1) : (b === 0 ? 1 : ap(cmp, [a['0'], b['0']])))",
}

RESULT = {
    "ok": "(x) => ({ $tag: 0, '0': x })",
    "error": "(e) => ({ $tag: 1, '0': e })",
    "is_ok": "(r) => (r.$tag === 0 ? 1 : 0)",
    "is_error": "(r) => (r.$tag === 1 ? 1 : 0)",
    "get_ok": "(r) => { if (r.$tag !== 0) throw new Error('Result.get_ok'); return r['0']; }",
    "get_error": "(r) => { if (r.$tag !== 1) throw new Error('Result.get_error'); return r['0']; }",
    "value": "(r, d) => (r.$tag === 0 ? r['0'] : d)",
    "map": "(f, r) => (r.$tag === 0 ? { $tag: 0, '0': ap(f, [r['0']]) } : r)",
    "map_error": "(f, r) => (r.$tag === 1 ? { $tag: 1, '0': ap(f, [r['0']]) } : r)",
    "bind": "(r, f) => (r.$tag === 0 ? ap(f, [r['0']]) : r)",
    "iter": "(f, r) => { if (r.$tag === 0) ap(f, [r['0']]); return 0; }",
    "iter_error": "(f, r) => { if (r.$tag === 1) ap(f, [r['0']]); return 0; }",
    "fold": "(ok_, err_, r) => (r.$tag === 0 ? ap(ok_, [r['0']]) : ap(err_, [r['0']]))",
    "to_option": "(r) => (r.$tag === 0 ? { $tag: 0, '0': r['0'] } : 0)",
    "retract": "(r) => r['0']",
    "to_list": "(r) => (r.$tag === 0 ? { $tag: 0, '0': r['0'], '1': 0 } : 0)",
    "equal": "(eq_ok, eq_err, a, b) => (a.$tag !== b.$tag ? 0 : ap(a.$tag === 0 ? eq_ok : eq_err, [a['0'], b['0']]))",
    "compare": "(cmp_ok, cmp_err, a, b) => (a.$tag !== b.$tag ? (a.$tag < b.$tag ? -1 : 1) : ap(a.$tag === 0 ? cmp_ok : cmp_err, [a['0'], b['0']]))",
}

CHAR = {
    "chr": "(n) => n",
    "compare": "(a, b) => (a < b ? -1 : a > b ? 1 : 0)",
    "equal": "(a, b) => (a === b ? 1 : 0)",
    "hash": "(c) => c",
    "seeded_hash": "(s, c) => c",
    "escaped": "(c) => (c === 39 ? \"\\\\'\" : c === 92 ? '\\\\\\\\' : c === 10 ? '\\\\n' : c === 9 ? '\\\\t' : c === 13 ? '\\\\r' : c === 8 ? '\\\\b' : (c < 32 || c > 126) ? '\\\\' + (c < 10 ? '00' : c < 100 ? '0' : '') + c : String.fromCharCode(c))",
    "lowercase_ascii": "(c) => (c >= 65 && c <= 90 ? c + 32 : c)",
    "uppercase_ascii": "(c) => (c >= 97 && c <= 122 ? c - 32 : c)",
    "is_digit": "(c) => (c >= 48 && c <= 57 ? 1 : 0)",
    "is_letter": "(c) => ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) ? 1 : 0)",
    "is_lower": "(c) => (c >= 97 && c <= 122 ? 1 : 0)",
    "is_upper": "(c) => (c >= 65 && c <= 90 ? 1 : 0)",
    "is_alphanum": "(c) => ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ? 1 : 0)",
    "is_white": "(c) => (c === 32 || c === 9 || c === 10 || c === 13 || c === 12 ? 1 : 0)",
    "is_blank": "(c) => (c === 32 || c === 9 ? 1 : 0)",
    "is_control": "(c) => ((c >= 0 && c <= 31) || c === 127 ? 1 : 0)",
    "is_graphic": "(c) => (c >= 33 && c <= 126 ? 1 : 0)",
    "is_print": "(c) => (c >= 32 && c <= 126 ? 1 : 0)",
    "is_hex_digit": "(c) => ((c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70) ? 1 : 0)",
    "is_valid": "(c) => (c >= 0 && c <= 255 ? 1 : 0)",
    "digit_to_int": "(c) => c - 48",
    "digit_of_int": "(n) => (n < 0 || n > 9 ? 255 : n + 48)",
    "hex_digit_to_int": "(c) => (c <= 57 ? c - 48 : (c & 0xdf) - 55)",
}

INT = {
    "abs": "(n) => Math.abs(n)",
    "compare": "(a, b) => (a < b ? -1 : a > b ? 1 : 0)",
    "equal": "(a, b) => (a === b ? 1 : 0)",
    "min": "(a, b) => (a < b ? a : b)",
    "max": "(a, b) => (a > b ? a : b)",
    "lognot": "(n) => ~n",
    "hash": "(n) => n",
    "seeded_hash": "(s, n) => n",
    "to_string": "(n) => String(n)",
}

SYS = {
    "catch_break": "(b) => 0",
    "set_signal": "(s, h) => 0",
    "signal_of_int": "(n) => n",
    "signal_to_int": "(s) => s",
    "signal_to_string": "(s) => String(s)",
}

FLOAT = {
    "succ": "(x) => x + 1",
    "pred": "(x) => x - 1",
    "is_finite": "(x) => (isFinite(x) ? 1 : 0)",
    "is_infinite": "(x) => (isFinite(x) ? 0 : (isNaN(x) ? 0 : 1))",
    "is_nan": "(x) => (isNaN(x) ? 1 : 0)",
    "is_integer": "(x) => (isFinite(x) && Math.floor(x) === x ? 1 : 0)",
    "float_of_string_opt": "(s) => { const n = parseFloat(s); return isNaN(n) ? 0 : { $tag: 0, '0': n }; }",
    "string_of_float": "(x) => String(x)",
    "equal": "(a, b) => (a === b ? 1 : 0)",
    "compare": "(a, b) => (a < b ? -1 : a > b ? 1 : 0)",
    "float_compare": "(a, b) => (a < b ? -1 : a > b ? 1 : 0)",
    "min": "(a, b) => (a < b ? a : b)",
    "max": "(a, b) => (a > b ? a : b)",
    "min_max": "(a, b) => (a < b ? { $tag: 0, '0': a, '1': b } : { $tag: 0, '0': b, '1': a })",
    "min_num": "(a, b) => (isNaN(a) ? b : isNaN(b) ? a : a < b ? a : b)",
    "max_num": "(a, b) => (isNaN(a) ? b : isNaN(b) ? a : a > b ? a : b)",
    "min_max_num": "(a, b) => (isNaN(a) ? { $tag: 0, '0': b, '1': b } : isNaN(b) ? { $tag: 0, '0': a, '1': a } : (a < b ? { $tag: 0, '0': a, '1': b } : { $tag: 0, '0': b, '1': a }))",
    "hash": "(x) => (x | 0)",
    "seeded_hash": "(s, x) => (x | 0)",
    "abs": "(x) => Math.abs(x)",
    "sqrt": "(x) => Math.sqrt(x)",
    "exp": "(x) => Math.exp(x)",
    "log": "(x) => Math.log(x)",
    "sin": "(x) => Math.sin(x)",
    "cos": "(x) => Math.cos(x)",
    "tan": "(x) => Math.tan(x)",
    "asin": "(x) => Math.asin(x)",
    "acos": "(x) => Math.acos(x)",
    "atan": "(x) => Math.atan(x)",
    "atan2": "(y, x) => Math.atan2(y, x)",
    "hypot": "(x, y) => Math.hypot(x, y)",
    "pow": "(x, y) => Math.pow(x, y)",
    "ceil": "(x) => Math.ceil(x)",
    "floor": "(x) => Math.floor(x)",
    "round": "(x) => Math.round(x)",
    "trunc": "(x) => Math.trunc(x)",
    "rem": "(x, y) => x % y",
    "fmod": "(x, y) => x % y",
    "modf": "(x) => ({ $tag: 0, '0': Math.trunc(x), '1': x - Math.trunc(x) })",
    "of_int": "(n) => n",
    "to_int": "(x) => Math.trunc(x)",
    "init": "(n, f) => { const a = new Array(n); for (let i = 0; i < n; i++) a[i] = ap(f, [i]); return a; }",
    "sub": "(a, ofs, len) => a.slice(ofs, ofs + len)",
    "copy": "(a) => a.slice()",
    "append": "(a, b) => a.concat(b)",
    "fill": "(a, ofs, len, v) => { for (let i = 0; i < len; i++) a[ofs + i] = v; return 0; }",
    "blit": "(a1, o1, a2, o2, len) => { for (let i = 0; i < len; i++) a2[o2 + i] = a1[o1 + i]; return 0; }",
    "to_list": "(a) => { let l = 0; for (let i = a.length - 1; i >= 0; i--) l = { $tag: 0, '0': a[i], '1': l }; return l; }",
    "of_list": "(l) => { const a = []; while (l !== 0) { a.push(l['0']); l = l['1']; } return a; }",
    "map": "(f, a) => a.map((x) => ap(f, [x]))",
    "map2": "(f, a, b) => a.map((x, i) => ap(f, [x, b[i]]))",
    "mapi": "(f, a) => a.map((x, i) => ap(f, [i, x]))",
    "iter": "(f, a) => { a.forEach((x) => ap(f, [x])); return 0; }",
    "iter2": "(f, a, b) => { a.forEach((x, i) => ap(f, [x, b[i]])); return 0; }",
    "iteri": "(f, a) => { a.forEach((x, i) => ap(f, [i, x])); return 0; }",
    "fold_left": "(f, init, a) => { let acc = init; for (let i = 0; i < a.length; i++) acc = ap(f, [acc, a[i]]); return acc; }",
    "fold_right": "(f, a, init) => { let acc = init; for (let i = a.length - 1; i >= 0; i--) acc = ap(f, [a[i], acc]); return acc; }",
    "exists": "(f, a) => (a.some((x) => ap(f, [x])) ? 1 : 0)",
    "for_all": "(f, a) => (a.every((x) => ap(f, [x])) ? 1 : 0)",
    "mem": "(x, a) => (a.some((v) => v === x) ? 1 : 0)",
    "mem_ieee": "(x, a) => (a.some((v) => v === x) ? 1 : 0)",
    "find_opt": "(f, a) => { const i = a.findIndex((x) => ap(f, [x])); return i < 0 ? 0 : { $tag: 0, '0': a[i] }; }",
    "find_index": "(f, a) => { for (let i = 0; i < a.length; i++) if (ap(f, [a[i]])) return i; throw new Error('Not_found'); }",
    "sort": "(cmp, a) => { a.sort((x, y) => ap(cmp, [x, y])); return 0; }",
    "stable_sort": "(cmp, a) => { a.sort((x, y) => ap(cmp, [x, y])); return 0; }",
}

INDEX_OVERRIDES = {
    "Stdlib": {21: "Infinity", 22: "-Infinity", 23: "NaN", 24: "1.7976931348623157e308", 25: "5e-324", 26: "2.220446049250313e-16"},
    "Float": {5: "Infinity", 6: "-Infinity", 7: "NaN", 8: "NaN", 9: "NaN", 11: "1.7976931348623157e308", 12: "5e-324", 13: "2.220446049250313e-16"},
}

IMPL_BY_UNIT = {
    "Stdlib": STDLIB,
    "Array": ARRAY,
    "String": STRING,
    "List": LIST,
    "Bytes": BYTES,
    "Hashtbl": HASHTBL,
    "Buffer": BUFFER,
    "Printf": PRINTF,
    "Option": OPTION,
    "Result": RESULT,
    "Char": CHAR,
    "Int": INT,
    "Sys": SYS,
    "Float": FLOAT,
}


def ocaml_where():
    return subprocess.check_output(["ocamlc", "-where"]).decode().strip()


def cmx_for(unit):
    return ocaml_where() + ("/stdlib.cmx" if unit == "Stdlib" else "/stdlib__" + unit + ".cmx")


def clambda_fields(cmx):
    txt = subprocess.check_output(["ocamlobjinfo", cmx]).decode()
    section = txt.split("Clambda approximation:", 1)[1]
    i, j = section.find("("), section.rfind(")")
    body = section[i + 1 : j]
    parts, depth, cur = [], 0, ""
    for ch in body:
        if ch == "(":
            depth += 1
        if ch == ")":
            depth -= 1
        if ch == ";" and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    fields = {}
    for p in parts:
        m = re.match(r"\s*(\d+):\s*(.*)", p.replace("\n", " ").strip())
        if m:
            fields[int(m.group(1))] = m.group(2).strip()
    return fields


def value_name(d):
    m = re.match(r"function\s+\S*\$([^\s]+?)_\d+", d)
    return m.group(1) if m else None


def const_value(d):
    m = re.match(r'const\((?:"[^"]*"=)?([-+]?[0-9][0-9.eE+-]*)\)$', d)
    return m.group(1) if m else None


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    out_path = args[0]
    unit = args[1] if len(args) > 1 else "Stdlib"
    impl = IMPL_BY_UNIT.get(unit, {})

    fields = clambda_fields(cmx_for(unit))
    n = max(fields) + 1

    lines = []
    lines.append("// Generated by scripts/gen-stdlib-shim.py from the OCaml %s layout." % unit)
    lines.append("// Do not edit by hand.")
    lines.append("function out(s) {")
    lines.append("  if (typeof process !== 'undefined' && process.stdout) process.stdout.write(String(s));")
    lines.append("  else if (typeof console !== 'undefined') console.log(String(s));")
    lines.append("}")
    lines.append("function ap(f, args) { return globalThis.OCamlRuntime ? globalThis.OCamlRuntime.caml_apply(f, args) : f.apply(null, args); }")
    if unit == "Printf":
        lines.extend(PRINTF_HELPERS)
    lines.append("const s = { $tag: 0 };")
    for i in range(n):
        lines.append(
            "s[%d] = function () { throw new Error('%s field %d not implemented'); };"
            % (i, unit, i)
        )

    stubs = 0
    implemented = 0
    for i in sorted(fields):
        d = fields[i]
        nm = value_name(d)
        if nm and nm in impl:
            lines.append("s[%d] = %s;" % (i, impl[nm]))
            implemented += 1
        elif nm:
            stubs += 1
        else:
            cv = const_value(d)
            if cv is not None:
                lines.append("s[%d] = %s;" % (i, cv))
    for i, v in INDEX_OVERRIDES.get(unit, {}).items():
        lines.append("s[%d] = %s;" % (i, v))
    lines.append("export default s;")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %s (%s): %d fields, %d implemented, %d stubs" % (out_path, unit, n, implemented, stubs))


if __name__ == "__main__":
    main()
