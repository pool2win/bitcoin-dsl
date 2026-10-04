# Conformance replay

The model is useful only if it is correct. Conformance replay checks it. Replay lowers a scenario log to real keys, signatures and transaction bytes. Then it replays the log against temporary regtest nodes and gives each step a status.

```racket
#lang bitcoin/conform
(define run (replay (scenario-log)
                    #:targets (hash 'mainnet (regtest)
                                    'signet  (regtest #:build 'inquisition))))
(summary run)          ; => ((confirmed 14) (disagree 0) (unverified 0))
(disagreements run)    ; the steps where the node and the model do not agree
(unverified-steps run) ; the steps that replay could not check, with #:reason
```

## Statuses

| Status | Description |
|---|---|
| `confirmed` | The node agrees with the model on consensus. |
| `disagree` | The node does not agree. The details give the `#:model` and `#:node` verdicts. A disagreement is a bug in the model, or an idea that depends on rules that do not exist. |
| `unverified` | Replay could not check the step. `#:reason` gives the cause (see the list below). |

These are the causes for `unverified`:

- `no-target`: the chain has no target.
- `target-binary-missing`: the node binary is not available.
- `(model-only-rule ctv)`: the step exercised a rule that the target runs differently.
- `spends-unverified-coin` or `includes-unverified-tx`: the step depends on an unverified step.
- A value that replay cannot lower.

No step passes without a check. A step is `confirmed` only after replay asks the node.

## How replay lowers values

- **Keys and secrets.** Replay derives them from their names (`sha256("bitcoin-dsl/key/<name>")`). Thus the real txids are the same for each run. Replay maps model txids to real txids, for each chain.
- **Scripts.** The opcode bytes come from the global registry, with minimal pushes. Segwit v0 scripts use compressed keys of 33 bytes. Tapscript uses x-only keys of 32 bytes.
- **Signatures.** Replay signs the BIP143 or BIP341 digest of the fields that the model signature committed to. It does not calculate the digest from the transaction that holds the signature. Thus a signature that is not valid in the model, for example on a changed transaction, is also not valid on the node.
- **Taproot.** Replay uses real tagged hashes: TapLeaf, TapBranch (with the children sorted by bytes), TapTweak and the control blocks.
- **CTV templates.** Replay lowers them to the real BIP119 hash.

The DSL has its own Racket code for secp256k1 ECDSA (RFC6979, low-S), BIP340 Schnorr, RIPEMD160 and HMAC. The tests compare this code with published test vectors.

!!! warning
    This crypto code does not run in constant time. Use it only with temporary regtest keys.

## Targets and different rules

A target is a node build and the consensus that it runs, as a model value:

| Target | Runs |
|---|---|
| `(regtest)` or `(regtest #:build 'core)` | `bitcoin`, with the `bitcoind` on `PATH`. |
| `(regtest #:build 'inquisition)` | `inquisition` (bitcoin plus CTV), with `BITCOIN_INQUISITION` or `~/projects/bitcoin-inquisition/build/bin/bitcoind`. |

Replay compares the consensus of the target with the consensus of the chain. It uses [`diff-consensus`](consensus.md#compare-rule-sets) for this comparison. A step that exercised an opcode or a rule in the differences is `unverified` with `(model-only-rule …)`. Replay does not use the answer of a node about a rule that the node runs differently.

For example, the CTV chain of Scenario 4 gives two such steps when it replays against Core. Against Inquisition, all steps are confirmed. Replay does not compare parameters. Thus a model with an incorrect parameter still shows as `disagree`.

## Consensus and policy

The replay nodes start with `-acceptnonstdtxn=1 -minrelaytxfee=0 -blockmintxfee=0 -dustrelayfee=0`. The RPC calls use `maxfeerate=0`.

A mempool can still refuse a transaction because of policy. For example, a transaction that uses NOP4 is not standard. In this case, replay asks if a block with the transaction is valid. It uses `generateblock` without submission and uses that answer. The step keeps the reason of the mempool as `#:mempool-only`. Replay mines these transactions in the next block.

Replay also checks each mined block: the height, the coinbase reward and the set of transactions in the block.

## The sighash matrix

```racket
(sighash-matrix #:spend-types '(wpkh tr-key tr-script) #:flags 'all #:target (regtest))
; => ((confirmed #:type wpkh #:flags (all) #:edit none #:model accepted) …)
```

For each spend type and each flag set, the matrix signs two inputs with those flags. Then it tries the transaction without an edit and with each edit. The edits change, add or remove outputs. They also change sequences, the version and the locktime, add a real input or remove an input. The matrix checks the verdict of the model for each cell against the node.

The matrix runs in a scratch session, thus it does not change your session. All 260 cells agree with Core. The model does not have legacy spends, thus they return `unsupported`.
