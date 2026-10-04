<!-- docs/gen-reference.rkt makes this page from the describe registry. Do not edit it. -->

# Forms

This page lists each form that the language exports for agents, in the groups of `(describe)`. Over MCP, `describe` with a form name returns the same usage and doc.

## Definition forms

These forms bind names: chains, keys, contracts, transactions and rule sets.

### `chain`

```racket
(chain name #:rules consensus)
```

Defines a chain with a new genesis block at height 0. Give chains names such as `mainnet` and `signet`, because `btc` is the amount constructor. The `bitcoin` rules use regtest parameters: a subsidy of 50 BTC that halves every 150 blocks, and a coinbase maturity of 100 blocks.

### `keys`

```racket
(keys name ...)
```

Binds each name to a key with that name. Keys are symbolic. Replay derives real keys from the names.

### `contract`

```racket
(contract name (param ...) policy)
```

Defines a function that makes a P2WSH lock from the parameters. The policy forms are `(pk k)`, `(sha256 s)`, `(older blocks)`, `(after height)`, `(ctv template)`, `(and p ...)`, `(or arm ...)` and `(thresh k (pk a) ...)`. An arm of `or` can have a label, `[label policy]`, and the label is the name of the spend path. `(older n)` counts the block of the coin: after the block that funds the coin, a `try` sees age 1, thus mine n-1 more blocks.

### `define-tx`

```racket
(define-tx name #:inputs ([coin input-option ...] ...) #:outputs ([label lock amount] ...))
```

Builds and signs a tx. It binds the tx to the name, and it binds each output label to the coin of that output as a top-level definition. A later `define-tx` with the same label binds the label again. The input options are the same as for `input`, for example `[cb #:sign alice #:sighash '(all anyonecanpay)]`.

## Values

These forms make amounts, locks, inputs, outputs and transactions.

### `secret`

```racket
(secret 'name)
```

Makes a hash preimage. Use it with `(sha256 s)` in contracts, and reveal it with `#:reveal`.

### `btc`

```racket
(btc 49.99)
```

Makes an amount in BTC. The amount is kept as an exact number of satoshis.

### `sats`

```racket
(sats 1000)
```

Makes an amount in satoshis.

### `wpkh`

```racket
(wpkh key)
```

Makes a P2WPKH lock.

### `tr`

```racket
(tr key #:leaves (list contract-lock ...))
```

Makes a taproot lock: a key path for the key, and one script leaf for each contract. The branches are `key`, then the leaf name or `leaf/path`.

### `input`

```racket
(input coin #:sign key-or-list #:path 'branch #:reveal secret-or-list #:sighash flags #:sequence n)
```

Makes the specification of one input. `#:path` selects a branch and sets nSequence and nLockTime. A signature or preimage that you do not give becomes an empty witness item. `#:sighash` is `'all`, `'none` or `'single`, or a list with `anyonecanpay`, for example `'(all anyonecanpay)`. Taproot also has `'default`.

### `output`

```racket
(output 'label lock amount)
```

Makes the specification of one output.

### `spend`

```racket
(spend coin-or-inputs #:sign key-or-list #:path 'branch #:reveal s #:sighash flags #:sequence n #:locktime n #:name 'name #:outputs (list (output 'label lock amount) ...))
```

Builds and signs a tx as an expression, for `try` and for the REPL. Use `out` to get its outputs. `#:path` sets nSequence and nLockTime for the branch, thus `#:sequence` and `#:locktime` are not usually necessary. To spend more than one coin, give a list of `(input ...)` specifications.

### `add-input`

```racket
(add-input tx coin #:sign key ...)  ; returns a tx named <name>+input
```

Adds an input at the end of the tx and signs only that input. The other signatures stay valid only if their sighash does not commit to the inputs.

### `edit`

```racket
(edit tx path value)
```

Returns the tx with one field changed. The witnesses do not change. The paths are `version`, `locktime`, `(input i sequence)`, `(output ref amount)`, `(output ref lock)`, `(inputs append)` with a coin, `(inputs remove i)`, `(outputs append)` with an `(output ...)` and `(outputs remove ref)`. `ref` is an output label or index. `i` is an input index.

## Consensus

These forms make, compare and audit rule sets.

### `define-consensus`

```racket
(define-consensus name #:extends parent #:opcodes (upgrade nop4 #:to ctv) #:rules (add r) (remove n) (replace n r) #:params (set k v) #:sighash (add version selector))
```

Defines a consensus value as a list of changes to a parent. For example, a soft fork changes an upgradable NOP to a proposal opcode (the known proposal is `ctv`). Give the value to `chain` with `#:rules`. The opcode names are not evaluated.

### `diff-consensus`

```racket
(diff-consensus a b)
```

Returns the changes from a to b: `(opcode #xb3 nop4 -> ctv)`, `(rule + name)`, `(rule - name)`, `(rule ~ name)`, `(param k old -> new)` and `(sighash + version)`.

### `template`

```racket
(template #:outputs (list (output ...)) #:version 2 #:locktime 0 #:inputs 1 #:sequences (...) #:index 0)
```

Makes a CTV (BIP119) template: the tx that must spend a coin with the lock `(ctv template)`. The default values agree with `spend` and `define-tx`.

### `audit`

```racket
(audit lock #:on chain)
```

Returns the places where a chain does not enforce the scripts of a lock as they are written, for example `(warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4)`. It returns `'()` if there is no problem.

## Session

These forms change or test the state of the chains.

### `mine`

```racket
(mine n #:on chain #:to key)
```

Mines n blocks. The first block includes the mempool. It returns the list of coinbase coins; put the call in `void` to discard them. Without `#:to`, the coinbases pay an anonymous miner, and no user key can spend them. Coinbases mature after 100 blocks. The subsidy halves every 150 blocks.

### `try`

```racket
(try tx)
```

Validates the tx against the chain and the mempool. It does not change the state. It returns `accepted` or `rejected`.

### `broadcast`

```racket
(broadcast tx)
```

Validates the tx. If the tx is accepted, it goes into the mempool. It returns `accepted` or `rejected`.

### `confirm`

```racket
(confirm tx)
```

Broadcasts the tx. If the tx is accepted, it mines one block with the coinbase to the anonymous miner. This spends the inputs permanently. To keep alternatives available, use `try` or `snapshot` first.

### `snapshot`

```racket
(snapshot)
```

Captures the chains and the scenario log. It does not capture Racket definitions.

### `restore`

```racket
(restore snapshot)
```

Puts the chains and the log back to a snapshot.

### `reset-session!`

```racket
(reset-session!)
```

Removes all chains, traces and the log.

## Queries

These forms read the state and return data.

### `output-of`

```racket
(output-of tx index)
```

Returns the coin at that output index.

### `out`

```racket
(out tx 'label)
```

Returns the coin with that label.

### `confirmed?`

```racket
(confirmed? tx)
```

Returns true if the tx is in a block.

### `height`

```racket
(height #:on chain)
```

Returns the height of the chain tip. If the session has only one chain, you can omit `#:on`.

### `utxos`

```racket
(utxos #:on chain #:spendable-by key #:locked-by lock)
```

Returns the confirmed coins in order of height, then outpoint. If the session has only one chain, you can omit `#:on`.

### `fee`

```racket
(fee tx)
```

Returns the inputs minus the outputs. A negative fee means that the outputs are more than the inputs. `try` rejects such a tx with `value-balance`.

### `branches`

```racket
(branches coin)
```

Returns the spend paths of the coin, each with the items that it needs.

### `last-trace`

```racket
(last-trace)
```

Returns the trace of the most recent `try` or `broadcast`.

### `explain`

```racket
(explain trace-or-id)
```

Returns a trace as data: each rule and each opcode that ran, in order. Stacks show the top item first. The rule that failed has its doc.

### `sig-of`

```racket
(sig-of tx input #:key key)
```

Returns the signature on an input.

### `commits`

```racket
(commits sig)
```

Returns the fields that a signature commits to. The list changes with the spend version and the flags. `(describe 'sighash)` gives the field names.

### `free-fields`

```racket
(free-fields tx)
```

Returns the edits from a fixed catalogue that keep every signature valid: `(inputs append)`, `(inputs remove-others)`, `(outputs append)`, `(output ref amount)`, `(output ref lock)`, `(input i sequence)`, `version` and `locktime`.

### `mutate`

```racket
(mutate tx path value)
```

Applies an edit and returns the signatures that the edit breaks, with the fields that changed. The paths are the same as for `edit`.

### `scenario-log`

```racket
(scenario-log)
```

Returns the log of chain, mine, try and broadcast events, the oldest first.

### `sighash-search`

```racket
(sighash-search tx #:goal (can (add-input) ...) #:keep (fixed (outputs all) ...) #:over '(wpkh tr-key tr-script))
```

Returns each `(spend-type flags)` with which the signers can sign so that the goal edits are free and the kept fields are not free. The goal words are `add-input`, `remove-inputs`, `add-output`, `change-outputs`, `change-version` and `change-locktime`. The keep words are `(outputs all)`, `(inputs all)`, `(output ref)`, `version` and `locktime`.

### `describe`

```racket
(describe) (describe 'topic)
```

Gives this help. The topics are `example`, a form name, a rule name, `rules`, `opcodes`, `state` and `forms`.

## Conformance

These forms replay a session against real nodes (`#lang bitcoin/conform`).

### `replay`

```racket
(replay (scenario-log) #:targets (hash 'mainnet (regtest) 'signet (regtest #:build 'inquisition)))
```

Replays the log against new regtest nodes, one node for each chain. Each step is `confirmed` (the node agrees on consensus), `disagree` or `unverified`. For an unverified step, `#:reason` gives the cause: no target, a rule that the target runs differently (`(model-only-rule ctv)`), a step that depends on an unverified step, or a value that replay cannot lower. A confirmed step with `#:mempool-only` is a tx that the mempool of the node refused because of policy, but that a block can include. Read a run with `summary`, `disagreements`, `unverified-steps`, `run-steps` and the `step-` accessors.

### `regtest`

```racket
(regtest #:build 'core|'inquisition #:bitcoind path)
```

Makes a replay target. `core` runs `bitcoin` with the `bitcoind` on PATH. `inquisition` runs `bitcoin` plus CTV (the consensus value `inquisition`). Replay finds it through `BITCOIN_INQUISITION` or at `~/projects/bitcoin-inquisition/build/bin/bitcoind`.

### `unverified-steps`

```racket
(unverified-steps run)
```

Returns the steps that replay could not check, each with its `#:reason`.

### `run-steps`

```racket
(run-steps run)
```

Returns all the steps of a run as `(status #:step n event detail)`. Read them with `step-n`, `step-status`, `step-event` and `step-detail`.

### `summary`

```racket
(summary run)
```

Returns the number of confirmed, disagree and unverified steps.

### `disagreements`

```racket
(disagreements run)
```

Returns the steps where the node and the model do not agree.

### `sighash-matrix`

```racket
(sighash-matrix #:spend-types '(wpkh tr-key tr-script) #:flags 'all #:target (regtest))
```

Checks the verdict of the model against a real node for each spend type, flag set and edit. It runs in a scratch session. It returns rows `(status #:type #:flags #:edit #:model ...)`.

