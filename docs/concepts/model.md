# The model

The model is a Bitcoin consensus engine for exploration. It keeps exact the parts of Bitcoin that decide validity: the fields that a signature commits to, the count of timelocks and the execution of scripts. The other parts are symbolic, thus the model can explain its results.

## Sessions and chains

A session holds one or more chains. You declare each chain with a consensus value. Each chain starts with a genesis block at height 0:

```racket
(chain mainnet #:rules bitcoin)
(chain signet  #:rules ctv-rules)
```

Each chain has its own height, simulated clock, UTXO set, mempool and blocks. The clock adds `block-spacing` seconds for each block. The `bitcoin` value uses regtest parameters, thus replays agree with a regtest node:

- The subsidy is 50 BTC, and it halves every 150 blocks.
- A coinbase output matures after 100 blocks.

The full session is one value that does not change. Thus `snapshot` and `restore` are fast. A snapshot captures the chains and the scenario log. `restore` keeps the traces, thus the trace ids in earlier results stay valid.

## Keys, secrets and symbolic crypto

```racket
(keys alice bob)          ; binds alice and bob to keys with the names alice and bob
(define s (secret 's1))   ; a hash preimage
```

Keys and secrets are names. A hash is a value that records the data that it hashes, for example `(hash160 alice)` or `(sha256 s1)`. A signature is `(sig key type fields)`. Here, `fields` is the list of `(field . value)` pairs that the signature commits to. The sighash selector of the chain selects these fields. Validation calculates the list again and compares the two lists. Thus you can examine the commitment of a signature directly with `commits`. If the lists are different, the rejection gives the fields that are different.

Replay [lowers](conformance.md) these values to real keys, real hashes and real ECDSA or Schnorr signatures. It derives the keys from the names.

## Amounts

`(btc 49.99)` and `(sats 1000)` make exact amounts in satoshis. They print as `(btc …)`. The DSL rounds a float to the nearest satoshi. It refuses an amount that is smaller than one satoshi.

## Coins

The DSL does not select coins for you. Each coin comes from one of these sources:

- `mine`, which returns the list of coinbase coins that it mined.
- An output with a label. `define-tx` binds each label. `(out tx 'label)` and `(output-of tx index)` also get an output.

`(utxos #:spendable-by bob)` returns the confirmed coins in a fixed order: confirmation height, then outpoint.

## Locks

A lock describes an output:

| Lock | Make it with |
|---|---|
| P2WPKH | `(wpkh key)` |
| P2WSH | A contract function, for example `(htlc alice bob s 144)`. See [Contracts](contracts.md). |
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

Each input can have these options:

- `#:sign` gives a key or a list of keys.
- `#:path` gives a spend path.
- `#:reveal` gives secrets.
- `#:sighash` gives the sighash flags.
- `#:sequence` gives the nSequence.

If you do not give a signature or a preimage, the witness gets an empty item. Thus an incomplete spend gives an explained rejection, not an error. The fee is the inputs minus the outputs: `(fee pay)`.

## Validate and mine

| Form | Effect |
|---|---|
| `(try tx)` | Validates the tx against the chain and the mempool. It does not change the state. |
| `(broadcast tx)` | Validates the tx. If the tx is accepted, the tx goes into the mempool. |
| `(confirm tx)` | Broadcasts the tx. If the tx is accepted, it mines one block. |
| `(mine n #:on chain #:to key)` | Mines `n` blocks. The first block includes the mempool. Without `#:to`, the coinbases pay an anonymous miner, and no user key can spend them. |

Each form returns a [result](../reference/results.md): `accepted` or `rejected`, with the step number in the scenario log and a trace id.

## The scenario log

Each new chain, each block mined, each `try` and each `broadcast` adds an event to the scenario log. The events hold the real model values:

- the consensus value of each chain;
- each exact transaction, its verdict, and the opcodes and rules that it exercised;
- the contents of each mined block.

`(scenario-log)` returns the log. The step numbers in results are positions in this log. After a `restore`, the log is the history of the current branch. [Replay](conformance.md) uses exactly this history.
