# Writing scenarios by hand

You can write the DSL directly as Racket modules. This is how the test suite is written, and it is the fastest way to iterate on the language itself.

## Two languages

| Language | Use |
|---|---|
| `#lang bitcoin/model` | All of Racket plus the modelling forms. No real nodes. |
| `#lang bitcoin/conform` | Everything in `bitcoin/model` plus `replay`, `regtest`, `sighash-matrix` and the run accessors. |

Both are full Racket: `define`, `for/list`, `require`, macros and `rackunit` all work. A module's top-level expressions print their values when run; wrap state-changing calls you do not want printed in `void`, e.g. `(void (mine 100 #:on mainnet))`.

## Skeleton

```racket
#lang bitcoin/conform
(require rackunit)

(chain mainnet #:rules bitcoin)
(keys alice bob)

(define cb (first (mine 1 #:on mainnet #:to alice)))
(void (mine 100 #:on mainnet))

(define-tx pay
  #:inputs  ([cb #:sign alice])
  #:outputs ([to-bob (wpkh bob) (btc 49.99)]))
(check-pred accepted? (confirm pay))

(check-equal? (cadr (assq 'disagree (summary (replay (scenario-log) #:targets (hash 'mainnet (regtest)))))) 0)
```

Run it with `racket file.rkt`, or as a test with `raco test file.rkt`.

## Conventions

- **Chain names.** Name chains `mainnet`, `signet` and so on. Do not name a chain `btc`: that is the amount constructor.
- **`define-tx` vs `spend`.** `define-tx` is a definition form: it binds the tx and every output label as top-level variables. `spend` is an expression for one-off `try` calls; reach its outputs with `(out tx 'label)`.
- **`mine` returns a list.** Use `(first (mine 1 …))` for a single coin.
- **One session per module.** The session state is per Racket namespace. Separate test files get separate sessions; within a file, use different chain names or `reset-session!`.
- **Many chains in a loop.** Definition forms work in internal-definition contexts, so `(for/list ([ch (list mainnet signet)]) (define-tx …) …)` works; see [Scenario 4](../scenarios/4-ctv.md).

## Testing patterns

Use `rackunit` on result values:

```racket
(define r (try refund))
(check-equal? (rejected-rule r) 'sequence-lock)
(check-equal? (result-detail r 'need) 144)
```

Test a property across many cases with plain Racket loops; [`tests/sighash.rkt`](https://github.com/pool2win/bitcoin-dsl/blob/main/racket-dsl/tests/sighash.rkt) checks `free-fields` against verification for every flag set and edit. Add a `replay` at the end of a scenario file to check it against Core; replay tests should skip when `bitcoind` is missing:

```racket
(if (find-executable-path "bitcoind")
    (let ([r (replay (scenario-log) #:targets (hash 'mainnet (regtest)))])
      (check-equal? (disagreements r) '()))
    (displayln "skipping replay: bitcoind not found"))
```
