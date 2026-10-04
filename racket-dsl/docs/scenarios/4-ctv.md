# Scenario 4: A CTV vault on two chains with different rules

**Goal:** run the same covenant on a chain with CTV and one without, and catch that it is silently unenforced where the opcode is still NOP4.

```racket
--8<-- "tests/scenario-4.rkt"
```

## What happens

- **The rule set.** `define-consensus` builds `ctv-rules` as bitcoin with NOP4 upgraded to CTV; `diff-consensus` shows that single change. See [Consensus as a value](../concepts/consensus.md).
- **The vault.** `template` describes the only transaction allowed to spend the coin (49.98 BTC to `cold`); `(contract vault () (ctv tmpl))` locks a coin to it.
- **Two chains.** The same code runs on both chains in a loop. The thief's spend, which ignores the template, is accepted on `mainnet`, where the script's `ctv` runs as NOP4 (`explain` shows `(op ctv #:as nop4 …)`). On `signet` it is rejected:

    ```racket
    (rejected #:chain signet #:rule ctv-template-mismatch #:input 0
              #:fields ((outputs all)) #:expected (…) #:got (…) …)
    ```

    The honest spend is accepted on both chains.

- **Audit.** `audit` warns before you trust the vault on mainnet: `((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))`, and returns `()` on signet.

The same pattern applies to any soft-fork proposal: CAT, CSFS, TXHASH or a new sighash mode would each be a proposal opcode or selector plus a `define-consensus`.

## Against real nodes

`tests/replay-4.rkt` replays the log twice:

| Targets | Result |
|---|---|
| mainnet on Core, signet on Bitcoin Inquisition | 14 confirmed. The thief's NOP4 spend is refused by Core's mempool as non-standard but a block would accept it (`#:mempool-only`), as the model says. |
| both chains on Core | 12 confirmed, 2 unverified: the two signet spends that run CTV come back `(model-only-rule ctv)`. |

**Forms used:** `define-consensus`, `#:extends`, `upgrade`, `diff-consensus`, `template`, `(ctv t)`, `audit`, several chains in one session.
