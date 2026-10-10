if (!globalThis.OCamlRuntime) {
(function () {
  "use strict";

  var ooId = 0;
  var namedValues = {};

  function out(s) {
    if (typeof process !== "undefined" && process.stdout && process.stdout.write) {
      process.stdout.write(s);
    } else if (typeof console !== "undefined" && console.log) {
      console.log(s);
    }
  }

  var KIND_NUM = 0,
    KIND_STR = 1,
    KIND_BLOCK = 2,
    KIND_FUN = 3,
    KIND_NULL = 4,
    KIND_OTHER = 5;

  function kind(x) {
    if (x === null || x === undefined) return KIND_NULL;
    var t = typeof x;
    if (t === "number") return KIND_NUM;
    if (t === "string") return KIND_STR;
    if (t === "function") return KIND_FUN;
    if (Array.isArray(x)) return KIND_BLOCK;
    if (t === "object" && x.$tag !== undefined) return KIND_BLOCK;
    return KIND_OTHER;
  }

  function blockTag(x) {
    return Array.isArray(x) ? 0 : x.$tag | 0;
  }

  function blockSize(x) {
    if (Array.isArray(x)) return x.length;
    var n = 0;
    for (var k in x) if (/^[0-9]+$/.test(k)) n++;
    return n;
  }

  function blockField(x, i) {
    return x[i];
  }

  function caml_compare(a, b) {
    var ka = kind(a),
      kb = kind(b);
    if (ka !== kb) return ka < kb ? -1 : 1;
    switch (ka) {
      case KIND_NUM:
        return a < b ? -1 : a > b ? 1 : 0;
      case KIND_STR:
        return a < b ? -1 : a > b ? 1 : 0;
      case KIND_BLOCK: {
        var ta = blockTag(a),
          tb = blockTag(b);
        if (ta !== tb) return ta < tb ? -1 : 1;
        var na = blockSize(a),
          nb = blockSize(b),
          n = na < nb ? na : nb;
        for (var i = 0; i < n; i++) {
          var r = caml_compare(blockField(a, i), blockField(b, i));
          if (r !== 0) return r;
        }
        return na < nb ? -1 : na > nb ? 1 : 0;
      }
      case KIND_FUN:
        throw new globalThis.Error("compare: functional value");
      default:
        return 0;
    }
  }

  function caml_closure(arity, f) {
    f.arity = arity;
    return f;
  }

  function caml_apply_core(f, args) {
    if (typeof f !== "function") throw new globalThis.Error("apply: not a function");
    var arity = f.arity;
    if (arity === undefined) return f.apply(null, args);
    if (args.length === arity) return f.apply(null, args);
    if (args.length < arity) {
      var partial = function () {
        return caml_apply_core(f, args.concat(Array.prototype.slice.call(arguments)));
      };
      partial.arity = arity - args.length;
      return partial;
    }
    return caml_apply_core(f.apply(null, args.slice(0, arity)), args.slice(arity));
  }

  function caml_trampoline(res) {
    while (res && res.tramp) res = caml_apply_core(res.tramp, res.args);
    return res;
  }

  function caml_apply(f, args) {
    return caml_trampoline(caml_apply_core(f, args));
  }

  // Adapter for passing an OCaml closure to a JS/WebSharper `fn` parameter,
  // which is invoked curried (f(a)(b)) by handwritten libraries.
  function caml_to_js(f) {
    if (typeof f !== "function" || f.arity === undefined) return f;
    var arity = f.arity;
    function curried() {
      var args = Array.prototype.slice.call(arguments);
      if (args.length >= arity) return caml_apply(f, args);
      return function () {
        return curried.apply(null, args.concat(Array.prototype.slice.call(arguments)));
      };
    }
    curried.arity = arity;
    return curried;
  }

  // Adapter for passing an OCaml list (cons cells, `0` for []) where JS/
  // WebSharper expects an IEnumerable; WebSharper accepts JS arrays there.
  function caml_list_to_array(xs) {
    var a = [];
    while (typeof xs === "object" && xs !== null) {
      a.push(xs[0]);
      xs = xs[1];
    }
    return a;
  }

  // RPC: the server bundle registers handlers by name. The client proxy calls
  // `rpcCall`, which serializes its arguments, transports them asynchronously to
  // the server, and resolves with the deserialized result.
  function registerRpc(name, fn) {
    var store = globalThis.OCamlRuntime.__serverRpc || (globalThis.OCamlRuntime.__serverRpc = {});
    store[name] = fn;
  }

  // Returns a Promise<result>. Arguments and result are JSON-round-tripped.
  function rpcCall(name, args) {
    var payload = JSON.stringify({ name: name, args: args });
    return globalThis.OCamlRuntime.rpcTransport(payload).then(function (response) {
      return JSON.parse(response).result;
    });
  }

  // Default transport: if `OCamlRuntime.rpcEndpoint` is set, POST the JSON
  // payload over HTTP to the native OCaml server; otherwise call the handler
  // in-process (used by tests without a running server).
  function rpcTransport(payload) {
    var endpoint = globalThis.OCamlRuntime.rpcEndpoint;
    if (endpoint) {
      return fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: payload,
      }).then(function (response) {
        return response.text();
      });
    }
    return Promise.resolve().then(function () {
      var p = JSON.parse(payload);
      var handler = (globalThis.OCamlRuntime.__serverRpc || {})[p.name];
      // Handlers may be synchronous or return an `Async.t` (a promise).
      return Promise.resolve(handler.apply(null, p.args)).then(function (result) {
        return JSON.stringify({ result: result });
      });
    });
  }

  // Async: on the client `Async.t` is a JS promise (see the rpc proxy). These
  // helpers adapt OCaml `Async.bind`/`map`/`run` closures to promise `.then`.
  function async_bind(p, cb) {
    return p.then(function (v) {
      return caml_to_js(cb)(v);
    });
  }

  function async_map(f, p) {
    return p.then(function (v) {
      return caml_to_js(f)(v);
    });
  }

  function async_run(f, p) {
    p.then(function (v) {
      caml_to_js(f)(v);
    });
    return 0;
  }

  function caml_trampoline_return(f, args) {
    return { tramp: f, args: args };
  }

  function caml_hash(x) {
    var h = 0;
    function mix(v) {
      h = (Math.imul(h, 31) + (v | 0)) | 0;
    }
    function walk(v) {
      switch (kind(v)) {
        case KIND_NUM:
          mix(v);
          break;
        case KIND_STR:
          mix(1);
          for (var i = 0; i < v.length; i++) mix(v.charCodeAt(i));
          break;
        case KIND_BLOCK: {
          mix(2 + blockTag(v));
          for (var j = 0, n = blockSize(v); j < n; j++) walk(blockField(v, j));
          break;
        }
        default:
          mix(7);
      }
    }
    walk(x);
    return h & 0x3fffffff;
  }

  globalThis.OCamlRuntime = {
    caml_fresh_oo_id: function () {
      return ++ooId;
    },
    caml_closure: caml_closure,
    caml_to_js: caml_to_js,
    caml_list_to_array: caml_list_to_array,
    registerRpc: registerRpc,
    rpcCall: rpcCall,
    rpcTransport: rpcTransport,
    async_bind: async_bind,
    async_map: async_map,
    async_run: async_run,
    caml_apply: caml_apply,
    caml_trampoline: caml_trampoline,
    caml_trampoline_return: caml_trampoline_return,
    caml_obj_tag: function (x) {
      switch (kind(x)) {
        case KIND_NUM:
          return 1000;
        case KIND_STR:
          return 252;
        case KIND_FUN:
          return 247;
        case KIND_BLOCK:
          return blockTag(x);
        case KIND_NULL:
          return 1000;
        default:
          return 248;
      }
    },
    caml_compare: caml_compare,
    caml_equal: function (a, b) {
      return caml_compare(a, b) === 0 ? 1 : 0;
    },
    caml_notequal: function (a, b) {
      return caml_compare(a, b) === 0 ? 0 : 1;
    },
    caml_lessthan: function (a, b) {
      return caml_compare(a, b) < 0 ? 1 : 0;
    },
    caml_lessequal: function (a, b) {
      return caml_compare(a, b) <= 0 ? 1 : 0;
    },
    caml_greaterthan: function (a, b) {
      return caml_compare(a, b) > 0 ? 1 : 0;
    },
    caml_greaterequal: function (a, b) {
      return caml_compare(a, b) >= 0 ? 1 : 0;
    },
    caml_hash: caml_hash,
    caml_is_int: function (x) {
      return typeof x === "number" && Number.isInteger(x) ? 1 : 0;
    },
    caml_is_out: function (i, a) {
      return i < 0 || i >= a.length ? 1 : 0;
    },
    caml_compare_ints: function (a, b) {
      return a < b ? -1 : a > b ? 1 : 0;
    },
    caml_compare_floats: function (a, b) {
      return a < b ? -1 : a > b ? 1 : 0;
    },
    caml_dup_array: function (a) {
      return a.slice();
    },
    caml_int64_of_string: function (s) {
      return BigInt(s);
    },
    caml_nativeint_of_string: function (s) {
      return BigInt(s);
    },
    caml_bint_of_int: function (kind, x) {
      return kind === "int32" ? x | 0 : BigInt(Math.trunc(x));
    },
    caml_int_of_bint: function (kind, x) {
      return kind === "int32" ? x : Number(x);
    },
    caml_bint_neg: function (kind, x) {
      return kind === "int32" ? -x | 0 : BigInt.asIntN(64, -x);
    },
    caml_bint_add: function (kind, a, b) {
      return kind === "int32" ? (a + b) | 0 : BigInt.asIntN(64, a + b);
    },
    caml_bint_sub: function (kind, a, b) {
      return kind === "int32" ? (a - b) | 0 : BigInt.asIntN(64, a - b);
    },
    caml_bint_mul: function (kind, a, b) {
      return kind === "int32" ? Math.imul(a, b) : BigInt.asIntN(64, a * b);
    },
    caml_bint_and: function (kind, a, b) {
      return kind === "int32" ? (a & b) | 0 : BigInt.asIntN(64, a & b);
    },
    caml_bint_or: function (kind, a, b) {
      return kind === "int32" ? (a | b) | 0 : BigInt.asIntN(64, a | b);
    },
    caml_bint_xor: function (kind, a, b) {
      return kind === "int32" ? (a ^ b) | 0 : BigInt.asIntN(64, a ^ b);
    },
    caml_bint_lsl: function (kind, a, b) {
      return kind === "int32" ? (a << b) | 0 : BigInt.asIntN(64, a << BigInt(b));
    },
    caml_bint_lsr: function (kind, a, b) {
      return kind === "int32" ? a >>> b : BigInt.asIntN(64, BigInt.asUintN(64, a) >> BigInt(b));
    },
    caml_bint_asr: function (kind, a, b) {
      return kind === "int32" ? a >> b : BigInt.asIntN(64, a >> BigInt(b));
    },
    caml_bint_div: function (kind, a, b) {
      return kind === "int32" ? (a / b) | 0 : a / b;
    },
    caml_bint_mod: function (kind, a, b) {
      return kind === "int32" ? a % b : a % b;
    },
    caml_bint_comp: function (kind, op, a, b) {
      var r;
      switch (op) {
        case "eq":
          return a === b ? 1 : 0;
        case "ne":
          return a !== b ? 1 : 0;
        case "lt":
          r = a < b;
          break;
        case "gt":
          r = a > b;
          break;
        case "le":
          r = a <= b;
          break;
        case "ge":
          r = a >= b;
          break;
        default:
          r = false;
      }
      return r ? 1 : 0;
    },
    caml_bint_compare: function (kind, a, b) {
      return a < b ? -1 : a > b ? 1 : 0;
    },
    caml_bint_conv: function (src, dst, x) {
      var v = typeof x === "bigint" ? x : BigInt(Math.trunc(x));
      return dst === "int32" ? Number(BigInt.asIntN(32, v)) : BigInt.asIntN(64, v);
    },
    caml_bint_bswap: function (kind, x) {
      if (kind === "int32") {
        return (((x & 0xff) << 24) | ((x & 0xff00) << 8) | ((x >>> 8) & 0xff00) | ((x >>> 24) & 0xff)) | 0;
      }
      var v = BigInt.asUintN(64, x);
      var r = 0n;
      for (var i = 0; i < 8; i++) r = (r << 8n) | ((v >> BigInt(8 * i)) & 0xffn);
      return BigInt.asIntN(64, r);
    },
    caml_bytes_set16: function (b, i, v) {
      b[i] = v & 0xff;
      b[i + 1] = (v >> 8) & 0xff;
      return 0;
    },
    caml_bytes_get16: function (b, i) {
      return b[i] | (b[i + 1] << 8);
    },
    caml_bytes_set32: function (b, i, v) {
      b[i] = v & 0xff;
      b[i + 1] = (v >> 8) & 0xff;
      b[i + 2] = (v >> 16) & 0xff;
      b[i + 3] = (v >> 24) & 0xff;
      return 0;
    },
    caml_bytes_get32: function (b, i) {
      return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
    },
    caml_bytes_set64: function (b, i, v) {
      var x = BigInt.asUintN(64, v);
      for (var j = 0; j < 8; j++) b[i + j] = Number((x >> BigInt(8 * j)) & 0xffn);
      return 0;
    },
    caml_bytes_get64: function (b, i) {
      var r = 0n;
      for (var j = 0; j < 8; j++) r |= BigInt(b[i + j]) << BigInt(8 * j);
      return BigInt.asIntN(64, r);
    },
    caml_bswap16: function (x) {
      return ((x & 0xff) << 8) | ((x >> 8) & 0xff);
    },
    caml_lazy_make: function (f) {
      return { $tag: 246, "0": f };
    },
    caml_lazy_make_forward: function (v) {
      return { $tag: 250, "0": v };
    },
    caml_obj_set_tag: function (x, tag) {
      x.$tag = tag;
      return 0;
    },
    caml_atomic_load: function (r) {
      return r["0"];
    },
    caml_atomic_cas_field: function (r, i, old, n) {
      if (r[i] === old) {
        r[i] = n;
        return 1;
      }
      return 0;
    },
    caml_register_named_value: function (name, v) {
      namedValues[name] = v;
      return 0;
    },
    caml_named_value: function (name) {
      return namedValues[name] || 0;
    },
    caml_int64_float_of_bits: function (x) {
      var buf = new ArrayBuffer(8);
      var view = new DataView(buf);
      var v = BigInt.asUintN(64, typeof x === "bigint" ? x : BigInt(x));
      view.setBigUint64(0, v, true);
      return view.getFloat64(0, true);
    },
    caml_ml_output: function (chan, s, ofs, len) {
      out(String(s).substr(ofs, len));
      return 0;
    },
    caml_ml_output_bytes: function (chan, b, ofs, len) {
      var s = "";
      for (var i = 0; i < len; i++) s += String.fromCharCode(b[ofs + i]);
      out(s);
      return 0;
    },
    caml_ml_output_char: function (chan, c) {
      out(String.fromCharCode(c));
      return 0;
    },
    caml_ml_flush: function (chan) {
      return 0;
    },
    caml_ml_close_channel: function (chan) {
      return 0;
    },
    caml_ml_input: function (chan, b, ofs, len) {
      return 0;
    },
    caml_ml_input_char: function (chan) {
      return -1;
    },
    caml_ml_input_scan_line: function (chan) {
      return 0;
    },
    caml_sys_exit: function (n) {
      throw new globalThis.Error("exit " + String(n));
    },
    caml_output_value: function (chan, v, flags) {
      throw new globalThis.Error("Marshal.output_value is not implemented");
    },
    caml_ml_open_descriptor_in: function (fd) {
      return 0;
    },
    caml_ml_open_descriptor_out: function (fd) {
      return 0;
    },
    caml_ml_set_binary_mode: function (chan, b) {
      return 0;
    },
    caml_ml_set_channel_name: function (chan, name) {
      return 0;
    },
    caml_ml_out_channels_list: function (unit_) {
      return 0;
    },
    caml_ml_seek_out: function (chan, pos) {
      return 0;
    },
    caml_lazy_update_to_forcing: function (x) {
      if (x.$tag === 246) {
        x.$tag = 244;
        return 0;
      }
      return 1;
    },
    caml_lazy_reset_to_lazy: function (x) {
      x.$tag = 246;
      return 0;
    },
    caml_lazy_update_to_forward: function (x) {
      x.$tag = 250;
      return 0;
    },
    caml_lazy_force: function (x) {
      var t = x === null || x === undefined ? 1000 : Array.isArray(x) ? 0 : typeof x === "object" && x.$tag !== undefined ? x.$tag : -1;
      if (t === 250) return x["0"];
      if (t === 244) throw new globalThis.Error("Lazy.Undefined");
      if (t !== 246) return x;
      x.$tag = 244;
      var f = x["0"];
      x["0"] = 0;
      try {
        var r = f(0);
        x["0"] = r;
        x.$tag = 250;
        return r;
      } catch (e) {
        x["0"] = function () {
          throw e;
        };
        x.$tag = 246;
        throw e;
      }
    },
    caml_create_bytes: function (n) {
      return new Uint8Array(n);
    },
    caml_bytes_of_string: function (s) {
      var a = new Uint8Array(s.length);
      for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i);
      return a;
    },
    caml_bytes_to_string: function (b) {
      var s = "";
      for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
      return s;
    },
    caml_string_of_bytes: function (b) {
      var s = "";
      for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
      return s;
    },
    caml_string_unsafe_get: function (s, i) {
      return s.charCodeAt(i);
    },
    caml_string_get: function (s, i) {
      return s.charCodeAt(i);
    },
    caml_bytes_unsafe_get: function (b, i) {
      return b[i];
    },
    caml_bytes_get: function (b, i) {
      return b[i];
    },
    caml_bytes_unsafe_set: function (b, i, c) {
      b[i] = c & 0xff;
      return 0;
    },
    caml_bytes_set: function (b, i, c) {
      b[i] = c & 0xff;
      return 0;
    },
    caml_ml_string_length: function (s) {
      return s.length;
    },
    caml_ml_bytes_length: function (b) {
      return b.length;
    },
    caml_string_concat: function (a, b) {
      return a + b;
    },
    caml_int_of_string: function (s) {
      var n = parseInt(s, 10);
      if (isNaN(n) || !/^\s*[+-]?[0-9]+\s*$/.test(s)) throw new globalThis.Error("Failure(\"int_of_string\")");
      return n;
    },
    caml_float_of_string: function (s) {
      var n = parseFloat(s);
      if (isNaN(n)) throw new globalThis.Error("Failure(\"float_of_string\")");
      return n;
    },
    caml_sqrt_float: Math.sqrt,
    caml_exp_float: Math.exp,
    caml_log_float: Math.log,
    caml_log10_float: Math.log10,
    caml_log2_float: Math.log2,
    caml_expm1_float: Math.expm1,
    caml_log1p_float: Math.log1p,
    caml_cos_float: Math.cos,
    caml_sin_float: Math.sin,
    caml_tan_float: Math.tan,
    caml_acos_float: Math.acos,
    caml_asin_float: Math.asin,
    caml_atan_float: Math.atan,
    caml_atan2_float: Math.atan2,
    caml_cosh_float: Math.cosh,
    caml_sinh_float: Math.sinh,
    caml_tanh_float: Math.tanh,
    caml_acosh_float: Math.acosh,
    caml_asinh_float: Math.asinh,
    caml_atanh_float: Math.atanh,
    caml_power_float: Math.pow,
    caml_hypot_float: Math.hypot,
    caml_ceil_float: Math.ceil,
    caml_floor_float: Math.floor,
    caml_cbrt_float: Math.cbrt,
    caml_abs_float: Math.abs,
    caml_round_float: Math.round,
    caml_trunc_float: Math.trunc,
    caml_exp2_float: function (x) {
      return Math.pow(2, x);
    },
    caml_fmod_float: function (x, y) {
      return x % y;
    },
    caml_ldexp_float: function (x, n) {
      return x * Math.pow(2, n);
    },
    caml_frexp_float: function (x) {
      if (x === 0 || !isFinite(x)) return { $tag: 0, "0": x, "1": 0 };
      var e = Math.ceil(Math.log2(Math.abs(x)));
      var frac = x / Math.pow(2, e);
      while (Math.abs(frac) >= 1) { frac /= 2; e += 1; }
      while (Math.abs(frac) < 0.5) { frac *= 2; e -= 1; }
      return { $tag: 0, "0": frac, "1": e };
    },
    caml_modf_float: function (x) {
      var i = Math.trunc(x);
      return { $tag: 0, "0": x - i, "1": i };
    },
    caml_fill_bytes: function (b, ofs, len, c) {
      for (var i = 0; i < len; i++) b[ofs + i] = c;
      return 0;
    },
    caml_blit_bytes: function (s1, i1, s2, i2, len) {
      for (var i = 0; i < len; i++) s2[i2 + i] = s1[i1 + i];
      return 0;
    },
    caml_blit_string: function (s1, i1, s2, i2, len) {
      for (var i = 0; i < len; i++) s2[i2 + i] = s1.charCodeAt(i1 + i);
      return 0;
    },
    caml_div: function (x, y) {
      if (y === 0) throw new globalThis.Error("Division_by_zero");
      return Math.trunc(x / y);
    },
    caml_mod: function (x, y) {
      if (y === 0) throw new globalThis.Error("Division_by_zero");
      return x % y;
    },
    caml_array_make: function (n, init) {
      var a = new Array(n);
      for (var i = 0; i < n; i++) a[i] = init;
      return a;
    },
    caml_make_vect: function (n, init) {
      var a = new Array(n);
      for (var i = 0; i < n; i++) a[i] = init;
      return a;
    },
    caml_obj_block: function (tag, size) {
      var o = { $tag: tag };
      for (var i = 0; i < size; i++) o[i] = 0;
      return o;
    },
    caml_obj_dup: function (x) {
      if (Array.isArray(x)) return x.slice();
      var o = { $tag: x.$tag };
      for (var k in x) o[k] = x[k];
      return o;
    },
    caml_obj_is_block: function (x) {
      return kind(x) === KIND_BLOCK ? 1 : 0;
    },
    caml_print_string: function (s) {
      out(String(s));
      return 0;
    },
    caml_print_bytes: function (s) {
      out(String(s));
      return 0;
    },
    caml_print_int: function (n) {
      out(String(n));
      return 0;
    },
    caml_print_float: function (f) {
      out(String(f));
      return 0;
    },
    caml_print_char: function (c) {
      out(String.fromCharCode(c));
      return 0;
    },
    caml_print_newline: function () {
      out("\n");
      return 0;
    },
    caml_print_endline: function (s) {
      out(String(s) + "\n");
      return 0;
    },
    caml_flush: function () {
      return 0;
    }
  };
})();
}
let a={};
const b=globalThis.OCamlRuntime.caml_create_bytes(3);
a=(b[0]=72,b[1]=105,b[2]=33,{$tag:0, "0":globalThis.OCamlRuntime.caml_bytes_to_string(b), "1":globalThis.OCamlRuntime.caml_string_unsafe_get("AB", 1)});
export default a;
