# Scenario 1: Fund and spend

**Goal:** the smallest end-to-end loop. Mine to Alice, pay Bob, confirm, query state.

```racket
--8<-- "tests/scenario-1.rkt"
```

## What happens

1. `(chain mainnet #:rules bitcoin)` creates a chain at height 0; `(keys alice bob)` binds two keys.
2. `mine` returns the list of coinbase coins, so `(first …)` is Alice's 50 BTC coin. A coinbase is spendable once it is 100 blocks deep, hence the 100 more blocks.
3. `define-tx` builds and signs the payment and binds `pay`, `to-bob` and `change`. `(broadcast pay)` returns `(accepted …)`, and the next block confirms it.
4. The queries return values: `(confirmed? pay)` is `#t`, Bob's only spendable coin is `to-bob`, and the fee is `(btc 0.001)`. The block that confirmed `pay` paid its miner 50.001 BTC.

Trying to spend too early is an explained rejection:

```racket
(rejected #:chain mainnet #:rule coinbase-maturity #:input 0 #:need 100 #:have 1 #:step 3 #:trace 1)
```

## Against a real node

`tests/replay-1.rkt` runs the same code in `#lang bitcoin/conform` and replays it against a regtest Bitcoin Core node: every step is confirmed, including Alice's real ECDSA signature and the 50.001 BTC block reward.

**Forms used:** `chain`, `keys`, `mine`, `define-tx`, `output-of`, `out`, `broadcast`, `confirmed?`, `utxos`, `fee`, `wpkh`.
