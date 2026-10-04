# Scenario 7: Conformance replay against regtest

**Goal:** take a scenario you are happy with in the model, lower it to real keys, signatures and transaction bytes, and replay it against real nodes step by step.

```racket
#lang bitcoin/conform
(define run1
  (replay (scenario-log)
          #:targets (hash 'mainnet (regtest)
                          'signet  (regtest #:build 'inquisition))))
(summary run1)   ; => ((confirmed 14) (disagree 0) (unverified 0))

(sighash-matrix #:spend-types '(legacy wpkh tr-key tr-script)
                #:flags 'all
                #:target (regtest))
; => ((confirmed #:type wpkh #:flags (all) #:edit none #:model accepted)
;     …
;     (unsupported #:type legacy))
```

Every runnable scenario has a replay test. Scenario 4's, against Core and Inquisition:

```racket
--8<-- "tests/replay-4.rkt"
```

And the sighash matrix:

```racket
--8<-- "tests/replay-matrix.rkt"
```

## What you learn

Which model results are backed by a real node. Steps using rules no target implements come back `unverified`, never silently confirmed. A disagreement is either a model bug or an idea that depends on rules that do not exist. Replay has caught real bugs during development: a key-format slip in taproot script-path signatures, and a SIGHASH_SINGLE edge case.

See [Conformance replay](../concepts/conformance.md) for how lowering, targets, the policy/consensus distinction and the matrix work.

**Forms used:** `replay`, `regtest`, `summary`, `disagreements`, `unverified-steps`, `run-steps`, `sighash-matrix`.
