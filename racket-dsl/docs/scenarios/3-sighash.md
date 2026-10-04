# Scenario 3: Sighash and fee bumps

**Goal:** Find the sighash flags that let Carol add a fee input to the signed payment of Alice. The signature of Alice must stay valid.

```racket
--8<-- "tests/scenario-3.rkt"
```

## What occurs

- **ANYONECANPAY.** Alice signs with `'(all anyonecanpay)`. `commits` shows that her signature commits to her own input and to all outputs, but not to the other inputs. Thus `free-fields` gives `(inputs append)` and `(inputs remove-others)`.
- **The fee bump.** `add-input` adds the 0.01 BTC coin of Carol and signs only that input. The new transaction is accepted, with a fee of 0.02 BTC.
- **The break.** `mutate` changes the amount for Bob. It shows that the signature of Alice breaks on `(outputs all)`.
- **The search.** `sighash-search` signs hypothetical copies of the payment again. It uses P2WPKH, taproot key-path and taproot script-path spends, and each valid flag set. With fixed outputs, only `(all anyonecanpay)` lets a different person add an input, for all three spend types. To also add outputs and keep the output of Bob fixed, the signer must use `(single anyonecanpay)`.
- **The contrast.** With SIGHASH_ALL only, `free-fields` is empty. The input of Carol gives a rejection with `eval-false`, `#:cause commitment-mismatch` and the changed `#:fields`.

[Signatures and sighash](../concepts/sighash.md) gives the field names and explains the queries.

## Against a real node

`tests/replay-3.rkt` replays the session against Core. A real node also accepts the ANYONECANPAY fee bump and rejects the SIGHASH_ALL fee bump. [`sighash-matrix`](7-conformance.md) checks the full table of flags and edits.

**Forms in this scenario:** `#:sighash`, `sig-of`, `commits`, `free-fields`, `mutate`, `add-input`, `sighash-search`, `can`, `fixed`.
