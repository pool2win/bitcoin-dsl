# Contracts and spend paths

## The policy language

`contract` defines a function from parameters to a lock:

```racket
(contract htlc (sender receiver secret timeout)
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(htlc alice bob s 144)   ; a P2WSH lock
```

| Fragment | Satisfied by |
|---|---|
| `(pk k)` | a signature by `k` |
| `(sha256 s)` | revealing the preimage `s` (a `secret`, or a sha256 digest when the preimage is unknown) |
| `(older n)` | the coin being `n` blocks deep (BIP68/BIP112; block-based only) |
| `(after h)` | a block height above `h` (BIP65 and nLockTime; height-based only) |
| `(ctv t)` | spending into the [CTV template](consensus.md#proposal-opcodes) `t` |
| `(and p …)` | all of them |
| `(or arm …)` | any arm; an arm may be labelled `[label policy]` |
| `(thresh k (pk a) …)` | `k` of the keys (only `pk` subs so far) |

Policies compile to Script as miniscript does: each fragment has a form that leaves true or false on the stack and one that verifies or aborts, and `or` becomes nested `IF`/`ELSE`. `(older n)` counts the coin's own block: right after the funding block is mined, a `try` sees age 1.

## Branches

A coin's spend paths, with what each needs:

```racket
(branches locked)
; => ((claim  #:needs ((sig bob) (preimage s1)))
;     (refund #:needs ((sig alice) (age>= 144))))
```

Labelled `or` arms name paths; unlabelled arms are named by position (`0`, `1`, …); nested labels join with `/` (`hot/first-key`); `thresh` paths are named by their keys (`alice+bob`). A P2WPKH coin has one path, `default`.

## Spending a path

```racket
(spend locked #:path 'refund #:sign alice
       #:outputs (list (output 'back (wpkh alice) (btc 49.98))))
(spend locked #:path 'claim #:sign bob #:reveal s
       #:outputs (list (output 'claimed (wpkh bob) (btc 49.98))))
```

`#:path` picks the branch, fills its witness template, and sets nSequence (for `older`) and nLockTime (for `after`), so `#:sequence` and `#:locktime` are rarely needed. A coin with several paths needs `#:path`. Anything the spender does not supply becomes an empty witness item, so the spend is rejected with an explanation (`#:cause empty-signature`, `equalverify` on a missing preimage) rather than failing to build.

## Taproot

```racket
(tr alice)                                            ; key path only
(tr carol #:leaves (list (htlc alice bob s 144)       ; key path plus script leaves
                         (single-key alice)))
```

Leaves are ordinary contracts arranged in a balanced tree. Branches are `key` for the key path, then each leaf's paths named after its contract: `htlc/claim`, `htlc/refund`, or `single-key-1`/`single-key-2` when two leaves share a contract. Tapscript differs from segwit v0 where Bitcoin does: a non-empty invalid signature fails `CHECKSIG` immediately, and signatures commit to the leaf. A key-path signature is modelled as made by the internal key, with the tweak implied by the symbolic output key. OP_SUCCESS, the annex and the sigops budget are not modelled.
