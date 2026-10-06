(function () {
  "use strict";

  var ooId = 0;

  function out(s) {
    if (typeof process !== "undefined" && process.stdout && process.stdout.write) {
      process.stdout.write(s);
    } else if (typeof console !== "undefined" && console.log) {
      console.log(s);
    }
  }

  globalThis.OCamlRuntime = {
    caml_fresh_oo_id: function () {
      return ++ooId;
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
