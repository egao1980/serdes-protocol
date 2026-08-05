# serdes-protocol

Minimal CLOS serialization/deserialization protocol for cl-stack logging and structured payloads.

| System | Role |
|--------|------|
| `serdes-protocol` | Format registry, backend generics, conditions, `encode` / `decode` |
| `sexp-protocol` | Built-in readable S-expression format backend (`:sexp`) |

Nick: `stack-serdes`.

## Quick use

```lisp
(asdf:load-system "sexp-protocol")
(sexp-protocol:use-sexp-backend)

(let ((record (make-hash-table :test 'equal)))
  (setf (gethash "msg" record) "hello"
        (gethash "null" record) :null)
  (stack-serdes:encode record :format :sexp))
```

Value mapping follows the cl-stack JSON shape: objects are string-key hash tables, arrays are vectors, and null is `:null`. The `:sexp` backend prints a readable S-expression representation with `prin1` and reads with `*read-eval*` bound to `nil`.

## Local tests

```sh
CL_SOURCE_REGISTRY="$(pwd)//:" ros -e '(asdf:test-system "serdes-protocol")' -q
```

CI uses `scripts/ci-install.lisp` and `scripts/ci-test.lisp` with cl-repository-client and Quicklisp fallbacks for `babel`, `trivial-gray-streams`, and `rove`.

## License

MIT -- see [LICENSE](LICENSE).
