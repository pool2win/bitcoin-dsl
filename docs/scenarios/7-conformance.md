# Scenario 7: Conformance replay against regtest

**Goal:** Take a scenario from the model and lower it to real keys, signatures and transaction bytes. Then replay it against real nodes, step by step.

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

Each scenario that runs has a replay test. This is the replay test of Scenario 4, against Core and Inquisition:

```racket
--8<-- "tests/replay-4.rkt"
```

This is the test of the sighash matrix:

```racket
--8<-- "tests/replay-matrix.rkt"
```

## What you learn

You learn which results of the model a real node supports. A step that uses rules that no target has returns `unverified`. Replay does not confirm such a step. A disagreement is a bug in the model, or an idea that depends on rules that do not exist. During the development, replay found real bugs: an error in the key format of taproot script-path signatures, and a special case of SIGHASH_SINGLE.

[Conformance replay](../concepts/conformance.md) explains how replay lowers values, the targets, the difference between policy and consensus, and the matrix.

**Forms in this scenario:** `replay`, `regtest`, `summary`, `disagreements`, `unverified-steps`, `run-steps`, `sighash-matrix`.
