# Contracts and spend paths

## The policy language

`contract` defines a function that makes a lock from parameters:

```racket
(contract htlc (sender receiver secret timeout)
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(htlc alice bob s 144)   ; a P2WSH lock
```

| Fragment | The spender must give |
|---|---|
| `(pk k)` | A signature by `k`. |
| `(sha256 s)` | The preimage `s`. `s` is a `secret`, or a sha256 digest if the preimage is not known. |
| `(older n)` | A coin that is `n` blocks deep (BIP68 and BIP112; blocks only). |
| `(after h)` | A block height above `h` (BIP65 and nLockTime; heights only). |
| `(ctv t)` | A spend into the [CTV template](consensus.md#proposal-opcodes) `t`. |
| `(and p …)` | All of the fragments. |
| `(or arm …)` | One of the arms. An arm can have a label: `[label policy]`. |
| `(thresh k (pk a) …)` | `k` of the keys. At this time, only `pk` fragments are permitted. |

The DSL compiles policies to Script as miniscript does. Each fragment has two forms. One form puts true or false on the stack. The other form stops the script if the condition is false. `or` becomes nested `IF` and `ELSE` opcodes. `(older n)` counts the block of the coin: after the block that funds the coin, a `try` sees age 1.

## Branches

`branches` returns the spend paths of a coin, with the items that each path needs:

```racket
(branches locked)
; => ((claim  #:needs ((sig bob) (preimage s1)))
;     (refund #:needs ((sig alice) (age>= 144))))
```

The names of the paths come from these sources:

- The label of an arm of `or` is the name of its path.
- An arm without a label gets its position as its name: `0`, `1` and so on.
- Labels in nested arms join with `/`, for example `hot/first-key`.
- The keys of a `thresh` path give its name, for example `alice+bob`.
- A P2WPKH coin has one path, `default`.

## Spend a path

```racket
(spend locked #:path 'refund #:sign alice
       #:outputs (list (output 'back (wpkh alice) (btc 49.98))))
(spend locked #:path 'claim #:sign bob #:reveal s
       #:outputs (list (output 'claimed (wpkh bob) (btc 49.98))))
```

`#:path` selects the branch and fills its witness template. It also sets nSequence for `older` and nLockTime for `after`. Thus `#:sequence` and `#:locktime` are not usually necessary. A coin with more than one path must have `#:path`.

If the spender does not give an item, the witness gets an empty item. Thus the spend gets a rejection with an explanation, not an error. For example, the rejection gives `#:cause empty-signature`, or `equalverify` if the preimage is not there.

## Taproot

```racket
(tr alice)                                            ; a key path only
(tr carol #:leaves (list (htlc alice bob s 144)       ; a key path and script leaves
                         (single-key alice)))
```

The leaves are usual contracts in a balanced tree. The branches have these names:

- `key` for the key path.
- The paths of each leaf, with the name of its contract: `htlc/claim` and `htlc/refund`.
- `single-key-1` and `single-key-2` when two leaves have the same contract.

Tapscript is different from segwit v0 where Bitcoin is different:

- A signature that is not empty and not valid makes `CHECKSIG` fail immediately.
- A signature commits to its leaf.

The model makes a key-path signature with the internal key. The symbolic output key contains the tweak. The model does not have OP_SUCCESS, the annex or the sigops budget.
