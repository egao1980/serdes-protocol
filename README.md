# serdes-protocol

CLOS **serialize / deserialize** protocol for [cl-stack](https://github.com/egao1980/cl-stack) — whole-value, Gray streams, JSONL, event/pull parse.

| System | Role | OCI |
|--------|------|-----|
| `serdes-protocol` (`stack-serdes`) | Format registry, Gray streams, JSONL, event GFs, media types | **0.3.0** |
| `sexp-protocol` | `:sexp` implementor (`prin1` / `read`, `*read-eval*` nil) | **0.3.0** |

JSON implementor: [`json-protocol`](https://github.com/egao1980/json-protocol) **0.2.0** (hard-depends this package).

**Cookbook:** [serdes.md](https://github.com/egao1980/cl-stack/blob/main/docs/cookbooks/serdes.md) · Brief: [serdes.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/serdes.md)

```lisp
(asdf:load-system "json-backend-jzon")   ; registers :json
(asdf:load-system "sexp-protocol")       ; registers :sexp

(stack-serdes:encode ht :format :json)
(stack-serdes:map-jsonl #'print source :format :json)
(stack-serdes:make-event-parser "[1,2]" :format :json)
(stack-serdes:format-media-type :json)              ; "application/json"
(stack-serdes:find-format-for-media-type "application/cbor")
```

Implementors call `register-format` (optionally `:media-type` / `:binary`). Binary formats default Gray streams to `(unsigned-byte 8)`.

**Errors** (0.3.0): `encode` / `decode` let a `serdes-error` through as signalled and turn any other backend `error` into `serdes-encode-error` / `serdes-decode-error`, signalled where the backend signalled it. The original is `serdes-error-cause`, and the backend's restarts stay active and associated, so a `handler-bind` around `decode` can invoke them: `(invoke-restart 'skip)`, `(use-value v e)`. The rules are in the header of `src/protocol.lisp`.


Object streams without formats → [`io-protocol`](https://github.com/egao1980/io-protocol).

## License

MIT — see [LICENSE](LICENSE).
