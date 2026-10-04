# Scenario 2: HTLC, timelocks and explained failures

**Goal:** define a contract, list its spend paths, try one too early, read why it failed, then fork the state to try both paths.

```racket
--8<-- "tests/scenario-2.rkt"
```

## What happens

- **The contract.** `contract` defines `htlc` as a function from its parameters to a P2WSH lock. The labelled `or` arms name the spend paths `claim` and `refund`; see [Contracts](../concepts/contracts.md).
- **Branches.** `(branches locked)` lists each path with what it needs: Bob's signature and the preimage, or Alice's signature and 144 blocks of age.
- **Too early.** `#:path 'refund` sets the input's nSequence to 144 and fills the witness. Spent one block after funding, the input fails BIP68's relative lock:

    ```racket
    (rejected #:chain mainnet #:rule sequence-lock #:input 0 #:need 144 #:have 1 …)
    ```

    The rule is `sequence-lock`, not the `csv` opcode: with nSequence set to 144, OP_CSV itself passes, and it is the input's relative lock that is not yet met. That matches what a real node reports (`non-BIP68-final`).

- **Explain.** The last step of `(explain (last-trace))` names the failing rule and carries its doc:

    ```racket
    (rule sequence-lock #:input 0 fail #:need 144 #:have 1
          #:doc "BIP68: an input whose nSequence encodes a relative lock waits that many blocks after its coin confirmed.")
    ```

- **Snapshots.** `snapshot` captures the chain; 143 more blocks make the refund valid; `restore` rewinds, and Bob's claim, revealing the preimage, is accepted instead.

## Against a real node

`tests/replay-2.rkt` replays the log, which after the `restore` holds the claim branch, against Core: the P2WSH script, the preimage, the CSV path and the BIP68 rejection all agree.

**Forms used:** `contract` (`pk`, `sha256`, `older`, `and`, `or`), `secret`, `branches`, `#:path`, `#:reveal`, `try`, `explain`, `snapshot`, `restore`.
