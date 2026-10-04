# Write scenarios by hand

You can write the DSL directly as Racket modules. The test suite uses this method. It is also the fastest method to change and test the language.

## The two languages

| Language | Use |
|---|---|
| `#lang bitcoin/model` | All of Racket plus the forms for models. It does not use real nodes. |
| `#lang bitcoin/conform` | All of `bitcoin/model` plus `replay`, `regtest`, `sighash-matrix` and the accessors for runs. |

Both languages are full Racket. You can use `define`, `for/list`, `require`, macros and `rackunit`. When you run a module, Racket prints the value of each top-level expression. To stop the print of a call that changes state, put it in `void`, for example `(void (mine 100 #:on mainnet))`.

## A skeleton

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

To run it, use `racket file.rkt`. To run it as a test, use `raco test file.rkt`.

## Conventions

- **Chain names.** Give chains names such as `mainnet` and `signet`. Do not give a chain the name `btc`, because `btc` is the amount constructor.
- **`define-tx` and `spend`.** `define-tx` is a definition form. It binds the tx and each output label as top-level variables. `spend` is an expression for a single `try`. To get its outputs, use `(out tx 'label)`.
- **`mine` returns a list.** For one coin, use `(first (mine 1 …))`.
- **One session for each module.** The session state is per Racket namespace. Each test file has its own session. In one file, use different chain names, or use `reset-session!`.
- **Many chains in a loop.** Definition forms operate in contexts that permit internal definitions. Thus `(for/list ([ch (list mainnet signet)]) (define-tx …) …)` is correct. See [Scenario 4](../scenarios/4-ctv.md).

## Patterns for tests

Use `rackunit` on the result values:

```racket
(define r (try refund))
(check-equal? (rejected-rule r) 'sequence-lock)
(check-equal? (result-detail r 'need) 144)
```

To test a property in many cases, use Racket loops. For example, [`tests/sighash.rkt`](https://github.com/pool2win/bitcoin-dsl/blob/main/tests/sighash.rkt) checks `free-fields` against validation for each flag set and each edit.

To check a scenario against Core, add a `replay` at the end of the file. Make the replay test stop without failure when `bitcoind` is not available:

```racket
(if (find-executable-path "bitcoind")
    (let ([r (replay (scenario-log) #:targets (hash 'mainnet (regtest)))])
      (check-equal? (disagreements r) '()))
    (displayln "skipping replay: bitcoind not found"))
```
