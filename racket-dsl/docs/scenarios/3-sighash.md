# Scenario 3: Sighash exploration and fee bumping

**Goal:** find which sighash flags let Carol add a fee input to Alice's signed payment without breaking Alice's signature.

```racket
--8<-- "tests/scenario-3.rkt"
```

## What happens

- **ANYONECANPAY.** Alice signs with `'(all anyonecanpay)`. `commits` shows her signature covers her own input and all outputs, but not the other inputs, so `free-fields` reports `(inputs append)` and `(inputs remove-others)`.
- **The bump.** `add-input` appends Carol's 0.01 BTC coin and signs only that input; the bumped transaction is accepted with a 0.02 BTC fee.
- **What breaks.** `mutate` changes Bob's amount and reports that Alice's signature breaks on `(outputs all)`.
- **Searching.** `sighash-search` re-signs hypothetical copies of the payment for P2WPKH, taproot key-path and taproot script-path spends and every valid flag set. With the outputs fixed, only `(all anyonecanpay)` lets anyone add an input, for all three. Allowing extra outputs while keeping Bob's fixed needs `(single anyonecanpay)`.
- **The contrast.** With plain SIGHASH_ALL, `free-fields` is empty and adding Carol's input is rejected with `eval-false`, `#:cause commitment-mismatch` and the changed `#:fields`.

See [Signatures and sighash](../concepts/sighash.md) for the field names and how the queries work.

## Against a real node

`tests/replay-3.rkt` replays the session against Core: the ANYONECANPAY bump is accepted and the SIGHASH_ALL bump rejected by a real node too. The full flag-by-edit grid is checked by [`sighash-matrix`](7-conformance.md).

**Forms used:** `#:sighash`, `sig-of`, `commits`, `free-fields`, `mutate`, `add-input`, `sighash-search`, `can`, `fixed`.
