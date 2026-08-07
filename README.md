# serdes-protocol

CLOS **serialize / deserialize** protocol for [cl-stack](https://github.com/egao1980/cl-stack) — whole-value, Gray streams, JSONL, event/pull parse.

| System | Role | OCI |
|--------|------|-----|
| `serdes-protocol` (`stack-serdes`) | Format registry, Gray streams, JSONL, event GFs | **0.2.0** |
| `sexp-protocol` | `:sexp` implementor (`prin1` / `read`, `*read-eval*` nil) | **0.2.0** |

JSON implementor: [`json-protocol`](https://github.com/egao1980/json-protocol) **0.2.0** (hard-depends this package).

**Cookbook:** [serdes.md](https://github.com/egao1980/cl-stack/blob/main/docs/cookbooks/serdes.md) · Brief: [serdes.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/serdes.md)

```lisp
(asdf:load-system "json-backend-jzon")   ; registers :json
(asdf:load-system "sexp-protocol")       ; registers :sexp

(stack-serdes:encode ht :format :json)
(stack-serdes:map-jsonl #'print source :format :json)
(stack-serdes:make-event-parser "[1,2]" :format :json)
```

Object streams without formats → [`io-protocol`](https://github.com/egao1980/io-protocol).

## License

MIT — see [LICENSE](LICENSE).
