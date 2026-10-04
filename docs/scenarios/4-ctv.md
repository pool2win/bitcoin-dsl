# Scenario 4: A CTV vault on two chains with different rules

**Goal:** Run the same covenant on a chain with CTV and on a chain without CTV. Find that the chain without CTV does not enforce the covenant, because there the opcode is still NOP4.

```racket
--8<-- "tests/scenario-4.rkt"
```

## What occurs

- **The rule set.** `define-consensus` makes `ctv-rules`: bitcoin with NOP4 changed to CTV. `diff-consensus` shows this one change. See [Consensus as a value](../concepts/consensus.md).
- **The vault.** `template` describes the only transaction that can spend the coin: 49.98 BTC to `cold`. `(contract vault () (ctv tmpl))` locks a coin to the template.
- **Two chains.** The same code runs on both chains in a loop.
    - The spend of the thief does not obey the template. `mainnet` accepts it, because there the `ctv` of the script runs as NOP4. `explain` shows `(op ctv #:as nop4 …)`.
    - `signet` rejects it:

        ```racket
        (rejected #:chain signet #:rule ctv-template-mismatch #:input 0
                  #:fields ((outputs all)) #:expected (…) #:got (…) …)
        ```

    - Both chains accept the honest spend.

- **The audit.** `audit` gives a warning before you trust the vault on mainnet: `((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))`. On signet, it returns `()`.

The same method applies to each soft-fork proposal. CAT, CSFS, TXHASH or a new sighash mode is a proposal opcode or a selector, with a `define-consensus`.

## Against real nodes

`tests/replay-4.rkt` replays the log two times:

| Targets | Result |
|---|---|
| mainnet on Core, signet on Bitcoin Inquisition | 14 confirmed. The mempool of Core refuses the NOP4 spend of the thief, because it is not standard. A block can include it, as the model says (`#:mempool-only`). |
| Both chains on Core | 12 confirmed and 2 unverified. The two signet spends that run CTV return `(model-only-rule ctv)`. |

**Forms in this scenario:** `define-consensus`, `#:extends`, `upgrade`, `diff-consensus`, `template`, `(ctv t)`, `audit`, more than one chain in a session.
