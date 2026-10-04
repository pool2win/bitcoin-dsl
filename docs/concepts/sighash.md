# Signatures and sighash

A model signature contains the list of fields that it commits to. Thus the DSL can answer signature questions directly:

- Which data does this signature protect?
- Which edits keep it valid?
- Which flags let a different person change the transaction?

## Flags

`#:sighash` is `'all`, `'none` or `'single`. `'all` is the default for segwit v0. Each flag can have `anyonecanpay` in a list, for example `'(all anyonecanpay)`. Taproot also has `'default`. It is the taproot default, and it commits to the same fields as `all`.

## The commitment of a signature

The field names refer to the input that signs: `own-input`, `own-prevout` and `own-output`. A digest binds the outpoint or the index of the input. Under ANYONECANPAY, the input can move to a different position.

**Segwit v0 (BIP143)**

- A signature always commits to `version`, `(own-input outpoint)`, `(own-input sequence)`, `(own-prevout script)`, `(own-prevout amount)` and `locktime`.
- Without ANYONECANPAY, it also commits to `(inputs outpoints)`. With ALL and without ANYONECANPAY, it also commits to `(inputs sequences)`.
- ALL commits to `(outputs all)`.
- SINGLE commits to `(own-output)`. If there is no output at the index of the input, it commits to no output.
- NONE commits to no output.

**Taproot (BIP341)**

- A signature always commits to `version`, `locktime` and `spend-type`.
- Without ANYONECANPAY, it commits to `(inputs outpoints)`, `(inputs amounts)`, `(inputs spks)`, `(inputs sequences)` and `(own-input index)`.
- With ANYONECANPAY, it commits to the outpoint, amount, spk and sequence of its own input.
- ALL and DEFAULT commit to `(outputs all)`.
- SINGLE commits to `(own-output)`. It is not valid if there is no such output.
- NONE commits to no output.
- A signature on a script path also commits to `(own-leaf)` and `codesep-position`.

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
| `(sig-of tx input #:key k)` | The signature on an input. |
| `(commits sig)` | The fields that the signature commits to. |
| `(edit tx path value)` | The tx with one field changed. The witnesses do not change. |
| `(mutate tx path value)` | The signatures that the edit breaks, with the fields that changed. |
| `(free-fields tx)` | The edits from the catalogue that no signature commits to. |
| `(add-input tx coin #:sign k)` | The tx with one more input at the end. Only that input gets a new signature. |

The edit paths are `version`, `locktime`, `(input i sequence)`, `(output ref amount)`, `(output ref lock)`, `(inputs append)`, `(inputs remove i)`, `(outputs append)` and `(outputs remove ref)`. `ref` is a label or an index.

`free-fields` checks these edits: `(inputs append)`, `(inputs remove-others)`, `(outputs append)`, the amount and lock of each output, the sequence of each input, `version` and `locktime`.

`mutate` and `free-fields` do not use rules about flags. They edit the transaction and calculate the commitment of each signature again with the selector that validation uses. Thus they cannot disagree with validation. A rejection for commitment-mismatch gives the same `#:fields`.

## Search for flags

`sighash-search` finds the spend types and flags that give the signers a property:

```racket
(sighash-search pay
  #:goal (can (add-input))
  #:keep (fixed (outputs all))
  #:over '(wpkh tr-key tr-script))
; => ((wpkh (all anyonecanpay)) (tr-key (all anyonecanpay)) (tr-script (all anyonecanpay)))
```

It signs hypothetical copies of the transaction again. In each copy, each signed input moves to a coin of a spend type, with a valid flag set. The search keeps the copies where each goal edit is free and no kept field is free. It does not change the chain.

- The goal words are `add-input`, `remove-inputs`, `add-output`, `change-outputs`, `change-version` and `change-locktime`.
- The keep words are `(outputs all)`, `(inputs all)`, `(output ref)`, `version` and `locktime`.

[`sighash-matrix`](conformance.md#the-sighash-matrix) checks the same properties against real nodes.
