# The model

The model is a Bitcoin consensus engine written for exploration. It keeps the parts of Bitcoin that decide validity exact (which fields a signature commits to, how timelocks count, how scripts run) and makes the rest symbolic, so that results can be explained.

## Sessions and chains

A session holds any number of chains. Each chain is declared with a consensus value and starts at a genesis block at height 0:

```racket
(chain mainnet #:rules bitcoin)
(chain signet  #:rules ctv-rules)
```

Each chain has its own height, simulated clock (`block-spacing` seconds per block), UTXO set, mempool and blocks. `bitcoin` uses regtest parameters so replays line up with a regtest node: a 50 BTC subsidy halving every 150 blocks, and coinbase maturity of 100 blocks.

The whole session is one immutable value, which is why `snapshot` and `restore` are cheap. A snapshot captures chains and the scenario log. Traces are kept across restores, so trace ids in earlier results stay valid.

## Keys, secrets and symbolic crypto

```racket
(keys alice bob)          ; binds alice and bob to keys named alice and bob
(define s (secret 's1))   ; a hash preimage
```

Keys and secrets are names. A hash is a structured value that records what was hashed: `(hash160 alice)`, `(sha256 s1)`. A signature is `(sig key type fields)`, where `fields` is the exact list of `(field . value)` pairs it commits to, chosen by the chain's sighash selector. Verification recomputes that list and compares. So a signature's commitment can be inspected directly (`commits`), and a mismatch names the fields that differ.

Replay [lowers](conformance.md) all of this to real keys (derived from the names), real hashes and real ECDSA or Schnorr signatures.

## Amounts

`(btc 49.99)` and `(sats 1000)` build exact satoshi amounts; they print as `(btc …)`. Floats are rounded to the satoshi, and anything finer than a satoshi is refused.

## Coins

Coins are never picked implicitly. Every coin comes from:

- `mine`, which returns the list of coinbase coins it mined; or
- a labelled transaction output: `define-tx` binds each label, and `(out tx 'label)` or `(output-of tx index)` looks one up.

`(utxos #:spendable-by bob)` queries confirmed coins in a fixed order: confirmation height, then outpoint.

## Locks

A lock is how an output is described:

| Lock | Built with |
|---|---|
| P2WPKH | `(wpkh key)` |
| P2WSH | a contract function, e.g. `(htlc alice bob s 144)` (see [Contracts](contracts.md)) |
| Taproot | `(tr key)` or `(tr key #:leaves (list (htlc …) …))` |

## Transactions

```racket
(define-tx pay                         ; a definition form
  #:inputs  ([cb #:sign alice])
  #:outputs ([to-bob (wpkh bob) (btc 49.99)]
             [change (wpkh alice) (btc 0.009)]))

(spend cb #:sign alice                 ; an expression
       #:outputs (list (output 'b (wpkh bob) (btc 49))))
```

Each input can take `#:sign` (a key or list), `#:path` (a spend path), `#:reveal` (secrets), `#:sighash` and `#:sequence`. Missing signatures or preimages become empty witness items, so an incomplete spend comes back as an explained rejection rather than a build error. The fee is inputs minus outputs: `(fee pay)`.

## Validating and mining

| Form | Effect |
|---|---|
| `(try tx)` | Validates against the chain and mempool; changes nothing. |
| `(broadcast tx)` | Validates; if accepted, adds to the mempool. |
| `(confirm tx)` | Broadcasts, then mines one block if accepted. |
| `(mine n #:on chain #:to key)` | Mines `n` blocks, including the mempool in the first. Without `#:to`, coinbases pay an anonymous miner no user key can spend. |

Each returns a [result](../reference/results.md): `accepted` or `rejected`, with the step number in the scenario log and a trace id.

## The scenario log

Every chain creation, mine, try and broadcast appends an event to the scenario log, holding the actual model values: the consensus value, the exact transaction, the verdict, the opcodes and rules it exercised, and what each mined block contained. `(scenario-log)` returns it. Step numbers in results are positions in this log. After a `restore`, the log is the history of the current branch, which is exactly what [replay](conformance.md) needs.
