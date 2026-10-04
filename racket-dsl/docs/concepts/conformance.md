# Conformance replay

The model is only useful if it is right. Conformance replay checks it: it lowers a scenario log to real keys, signatures and transaction bytes, replays it against throwaway regtest nodes, and gives every step a status.

```racket
#lang bitcoin/conform
(define run (replay (scenario-log)
                    #:targets (hash 'mainnet (regtest)
                                    'signet  (regtest #:build 'inquisition))))
(summary run)          ; => ((confirmed 14) (disagree 0) (unverified 0))
(disagreements run)    ; steps where the node and the model differ
(unverified-steps run) ; steps replay could not check, with #:reason
```

## Statuses

| Status | Meaning |
|---|---|
| `confirmed` | The node agrees with the model, on consensus. |
| `disagree` | It does not. The detail shows `#:model` and `#:node` verdicts. A disagreement is a model bug, or an idea that depends on rules that do not exist. |
| `unverified` | The step could not be checked. `#:reason` says why: `no-target`, `target-binary-missing`, `(model-only-rule ctv)` when the step exercised a rule the target runs differently, `spends-unverified-coin` or `includes-unverified-tx` when it depends on such a step, or something lowering cannot express. |

Nothing passes silently: a step is only `confirmed` after the node has actually been asked.

## Lowering

- **Keys and secrets** are derived from their names (`sha256("bitcoin-dsl/key/<name>")`), so real txids are the same on every run. Model txids map to real ones during replay, per chain.
- **Scripts** take opcode bytes from the global registry, with minimal pushes. Keys are 33-byte compressed in segwit v0 scripts and 32-byte x-only in tapscript.
- **Signatures** are made over the BIP143 or BIP341 digest *rebuilt from the fields the model signature committed to*, not from the transaction it sits in. A signature that is invalid in the model (say, over a tampered transaction) is invalid on the node too.
- **Taproot** uses real tagged hashes: TapLeaf, TapBranch (children sorted by bytes), TapTweak and control blocks.
- **CTV templates** lower to the real BIP119 hash.

secp256k1 ECDSA (RFC6979, low-S), BIP340 Schnorr, RIPEMD160 and HMAC are implemented in plain Racket and checked against published test vectors. They are not constant time: this is for throwaway regtest keys only.

## Targets and differing rules

A target is a node build plus the consensus it runs, as a model value:

| Target | Runs |
|---|---|
| `(regtest)` or `(regtest #:build 'core)` | `bitcoin`, using `bitcoind` on `PATH` |
| `(regtest #:build 'inquisition)` | `inquisition` (bitcoin plus CTV), using `BITCOIN_INQUISITION` or `~/projects/bitcoin-inquisition/build/bin/bitcoind` |

Replay compares the target's consensus with the chain's using [`diff-consensus`](consensus.md#comparing-rule-sets). A step that exercised an opcode or rule in that diff is `unverified` with `(model-only-rule …)`, rather than reading the node's answer as a verdict on a rule it runs differently. Replaying the CTV chain of Scenario 4 against Core gives exactly two such steps; against Inquisition, all steps confirm. Parameters are not gated, so a model with a wrong parameter still shows up as a `disagree`.

## Consensus, not policy

Replay nodes run with `-acceptnonstdtxn=1 -minrelaytxfee=0 -blockmintxfee=0 -dustrelayfee=0`, and RPC calls pass `maxfeerate=0`. When a mempool still refuses a transaction (using NOP4 is non-standard, for example), replay asks whether a block containing it would be valid (`generateblock` without submitting) and uses that answer; the mempool's reason is kept as `#:mempool-only`. Transactions a block would accept but the mempool refused are mined explicitly in the next block. Mined blocks are checked for height, coinbase reward and the set of included transactions.

## The sighash matrix

```racket
(sighash-matrix #:spend-types '(wpkh tr-key tr-script) #:flags 'all #:target (regtest))
; => ((confirmed #:type wpkh #:flags (all) #:edit none #:model accepted) …)
```

For every spend type and flag set, two inputs are signed with those flags, and the transaction is tried unedited and under every edit (outputs changed, appended or removed, sequences, version, locktime, a real input appended, an input removed). The model's verdict for each cell is checked against the node. It runs in a scratch session, so the caller's session is untouched. All 260 cells agree with Core. Legacy spends are not modelled and come back `unsupported`.
