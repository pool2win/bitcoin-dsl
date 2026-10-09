# Scenario 5: Litecoin with bitcoin, and an atomic swap

!!! note "Planned for v2"
    This scenario has a design, but it is not built. The code below shows the proposed syntax. You cannot run it yet.

**Goal:** Run litecoin as a second real chain next to bitcoin. Then build a contract that spans the two chains: an atomic swap of the LTC of Alice for the BTC of Bob. Drive the swap step by step on one shared clock. Show that you must compare the timeouts in wall time. Show the order of events that loses money when the timeouts are in the wrong order.

```racket
#lang bitcoin/conform
(chain mainnet #:rules bitcoin)     ; 10-minute blocks
(chain litenet #:rules litecoin)    ; 2.5-minute blocks, 84M supply
(keys alice bob)
(define s (secret 'swap))

(contract swap-htlc (sender receiver secret timeout)
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(define a-coin (first (mine 1 #:on litenet #:to alice)))   ; Alice has LTC
(define b-coin (first (mine 1 #:on mainnet #:to bob)))     ; Bob has BTC
(advance (hours 17))   ; one clock: mines 102 btc blocks and 408 ltc blocks

;; Alice knows s and locks first, with the longer timeout.
(define-tx alice-lock
  #:inputs  ([a-coin #:sign alice])
  #:outputs ([on-ltc (swap-htlc alice bob s 576) (ltc 49.99)]))   ; 576 ltc blocks = 24 h
(confirm alice-lock)
(define-tx bob-lock
  #:inputs  ([b-coin #:sign bob])
  #:outputs ([on-btc (swap-htlc bob alice s 72) (btc 49.99)]))    ; 72 btc blocks = 12 h
(confirm bob-lock)

(refund-times on-ltc on-btc)
; => ((on-ltc #:chain litenet #:refund-after (hours 24))
;     (on-btc #:chain mainnet #:refund-after (hours 12)))
(swap-check #:initiator on-ltc #:participant on-btc)
; => ()   the refund of the initiator opens after the refund of the participant

;; Alice claims the BTC. This reveals s on mainnet. Bob reads s and claims the LTC.
(define claim-btc (spend on-btc #:path 'claim #:sign alice #:reveal s
                    #:outputs (list (output 'a (wpkh alice) (btc 49.98)))))
(confirm claim-btc)
(revealed claim-btc)                      ; => (list s)
(confirm (spend on-ltc #:path 'claim #:sign bob #:reveal s
           #:outputs (list (output 'b (wpkh bob) (ltc 49.98)))))

(replay (scenario-log) #:targets (hash 'mainnet (regtest)
                                       'litenet (regtest #:build 'litecoin)))
```

## The incorrect variant

Make the LTC lock of Alice 144 litecoin blocks, which is 6 hours. That is shorter than the 12 hours of the BTC lock of Bob. `swap-check` gives a warning:

```racket
((warning #:initiator-refund-first (hours 6) #:participant-refund (hours 12)))
```

The model can show the loss step by step:

1. After 6 hours, Alice gets her LTC back with the refund path.
2. Before 12 hours, Alice also claims the BTC of Bob with `s`.
3. Bob cannot claim the LTC, because Alice already spent it.

## Why this scenario is important

The DSL must model more than one real chain, with contracts that span them. Litecoin uses the same script, segwit, taproot and sighash rules as bitcoin. Its consensus parameters are different: a block every 150 seconds and a maximum of 84 million LTC. Litecoin Core can check each step of a replay, as Bitcoin Core does for bitcoin.

An agent will learn these facts:

- A contract across chains is safe only if its timeouts are in the correct order in wall time.
- Block counts on chains with different block intervals are not comparable.
- A secret that a spend reveals on one chain is visible to the other party.

We will make and check our contracts between bitcoin and litecoin first. [Scenario 6](6-swap.md) then lets an agent search for bad orders of events automatically.

**This scenario will need these items:**

- A `litecoin` consensus value and an `ltc` amount constructor.
- One simulated clock for all chains: `advance`, `hours`, `now`, and the wall time of a number of blocks.
- `refund-times`, `swap-check` and `revealed`.
- A Litecoin Core replay target. The model does not have MWEB, the extension blocks of litecoin.
