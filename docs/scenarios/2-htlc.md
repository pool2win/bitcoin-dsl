# Scenario 2: HTLC, timelocks and explained failures

**Goal:** Define a contract and list its spend paths. Try one path too early and read the cause of the failure. Then use a snapshot to try both paths.

```racket
--8<-- "tests/scenario-2.rkt"
```

## What occurs

- **The contract.** `contract` defines `htlc` as a function that makes a P2WSH lock from its parameters. The labels on the arms of `or` give the names of the spend paths: `claim` and `refund`. See [Contracts](../concepts/contracts.md).
- **The branches.** `(branches locked)` lists each path with the items that it needs. The claim needs the signature of Bob and the preimage. The refund needs the signature of Alice and an age of 144 blocks.
- **Too early.** `#:path 'refund` sets the nSequence of the input to 144 and fills the witness. One block after the fund transaction, the input does not pass the relative lock of BIP68:

    ```racket
    (rejected #:chain mainnet #:rule sequence-lock #:input 0 #:need 144 #:have 1 …)
    ```

    The rule is `sequence-lock`, not the `csv` opcode. The nSequence is 144, thus OP_CSV passes. The relative lock of the input is the check that fails. A real node gives the same result (`non-BIP68-final`).

- **Explain.** The last step of `(explain (last-trace))` gives the rule that failed and its doc:

    ```racket
    (rule sequence-lock #:input 0 fail #:need 144 #:have 1
          #:doc "BIP68: an input whose nSequence encodes a relative lock waits that many blocks after its coin confirmed.")
    ```

- **Snapshots.** `snapshot` captures the chain. After 143 more blocks, the refund is valid. `restore` puts the chain back. Then the claim of Bob, with the preimage, is accepted.

## Against a real node

`tests/replay-2.rkt` replays the log against Core. After the `restore`, the log holds the claim branch. The P2WSH script, the preimage, the CSV path and the BIP68 rejection all agree with Core.

**Forms in this scenario:** `contract` (`pk`, `sha256`, `older`, `and`, `or`), `secret`, `branches`, `#:path`, `#:reveal`, `try`, `explain`, `snapshot`, `restore`.
