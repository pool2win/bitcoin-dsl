# Scenario 1: Fund and spend

**Goal:** Do the smallest loop from start to end. Mine to Alice, pay Bob, confirm the payment and read the state.

```racket
--8<-- "tests/scenario-1.rkt"
```

## What occurs

1. `(chain mainnet #:rules bitcoin)` makes a chain at height 0. `(keys alice bob)` binds two keys.
2. `mine` returns the list of coinbase coins. Thus `(first …)` is the 50 BTC coin of Alice. A coinbase output matures after 100 blocks, thus the scenario mines 100 more blocks.
3. `define-tx` builds and signs the payment, and binds `pay`, `to-bob` and `change`. `(broadcast pay)` returns `(accepted …)`. The next block confirms the payment.
4. The queries return values. `(confirmed? pay)` is `#t`. The only coin that Bob can spend is `to-bob`. The fee is `(btc 0.001)`. The block that confirmed `pay` paid 50.001 BTC to its miner.

A spend that is too early gives an explained rejection:

```racket
(rejected #:chain mainnet #:rule coinbase-maturity #:input 0 #:need 100 #:have 1 #:step 3 #:trace 1)
```

## Against a real node

`tests/replay-1.rkt` runs the same code in `#lang bitcoin/conform`. It replays the code against a regtest Bitcoin Core node. Each step is confirmed, which includes the real ECDSA signature of Alice and the block reward of 50.001 BTC.

**Forms in this scenario:** `chain`, `keys`, `mine`, `define-tx`, `output-of`, `out`, `broadcast`, `confirmed?`, `utxos`, `fee`, `wpkh`.
