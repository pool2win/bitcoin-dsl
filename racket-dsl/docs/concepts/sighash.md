# Signatures and sighash

A model signature carries the exact list of fields it commits to. That makes signature questions answerable directly: what does this signature protect, which edits leave it valid, and which flags would let someone else change the transaction?

## Flags

`#:sighash` is `'all` (the segwit v0 default), `'none` or `'single`, or a list adding `anyonecanpay`, e.g. `'(all anyonecanpay)`. Taproot also has `'default` (its default, which commits like `all`).

## What a signature commits to

Field names are relative to the signing input (`own-input`, `own-prevout`, `own-output`), because a digest binds the input's outpoint (or index), not its position under ANYONECANPAY.

**Segwit v0 (BIP143).** Always: `version`, `(own-input outpoint)`, `(own-input sequence)`, `(own-prevout script)`, `(own-prevout amount)`, `locktime`. Without ANYONECANPAY, `(inputs outpoints)`, and with ALL also `(inputs sequences)`. ALL commits `(outputs all)`; SINGLE commits `(own-output)` (or no outputs when there is none at the input's index); NONE commits no outputs.

**Taproot (BIP341).** Always: `version`, `locktime`, `spend-type`. Without ANYONECANPAY: `(inputs outpoints)`, `(inputs amounts)`, `(inputs spks)`, `(inputs sequences)` and `(own-input index)`; with it: the own input's outpoint, amount, spk and sequence. ALL/DEFAULT commit `(outputs all)`; SINGLE commits `(own-output)` and is invalid when there is none; NONE commits no outputs. A script-path signature adds `(own-leaf)` and `codesep-position`.

`(describe 'sighash)` returns the same summary.

## The queries

```racket
(commits (sig-of pay 0))
; => (version (own-input outpoint) (own-prevout script) (own-prevout amount)
;     (own-input sequence) (outputs all) locktime)

(free-fields pay)                ; => ((inputs append) (inputs remove-others))

(mutate pay '(output to-bob amount) (btc 49.0))
; => (breaks ((sig alice 0 #:fields ((outputs all)))))
```

| Form | Returns |
|---|---|
| `(sig-of tx input #:key k)` | the signature on an input |
| `(commits sig)` | the fields it commits to |
| `(edit tx path value)` | the tx with one field changed, witnesses kept |
| `(mutate tx path value)` | the signatures that edit breaks, with the fields that changed |
| `(free-fields tx)` | the catalogued edits no signature commits to |
| `(add-input tx coin #:sign k)` | the tx with an input appended and only that input signed |

Edit paths: `version`, `locktime`, `(input i sequence)`, `(output ref amount)`, `(output ref lock)`, `(inputs append)`, `(inputs remove i)`, `(outputs append)`, `(outputs remove ref)`; `ref` is a label or index. `free-fields` checks `(inputs append)`, `(inputs remove-others)`, `(outputs append)`, every output's amount and lock, every input's sequence, `version` and `locktime`.

`mutate` and `free-fields` never reason about flags: they edit the transaction and recompute each signature's commitment with the selector verification uses, so they cannot disagree with it. A commitment-mismatch rejection carries the same `#:fields`.

## Searching for flags

`sighash-search` asks which spend types and flags would give the signers a property:

```racket
(sighash-search pay
  #:goal (can (add-input))
  #:keep (fixed (outputs all))
  #:over '(wpkh tr-key tr-script))
; => ((wpkh (all anyonecanpay)) (tr-key (all anyonecanpay)) (tr-script (all anyonecanpay)))
```

It re-signs hypothetical copies of the transaction, with each signed input moved to a coin of each spend type and each valid flag set, and keeps those where every goal edit is free and no kept field is. Goal words: `add-input`, `remove-inputs`, `add-output`, `change-outputs`, `change-version`, `change-locktime`. Keep words: `(outputs all)`, `(inputs all)`, `(output ref)`, `version`, `locktime`. Nothing touches the chain.

The same properties are checked against real nodes with [`sighash-matrix`](conformance.md#the-sighash-matrix).
