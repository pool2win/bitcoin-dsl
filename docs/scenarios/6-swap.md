# Scenario 6: Swap between chains, with actors and faults

!!! note "Planned for v3"
    This scenario has a design, but it is not built. The code below shows the proposed syntax. You cannot run it yet.

**Goal:** Do the swap of [Scenario 5](5-litecoin-swap.md) with actors, not by hand. Explore the orders of events and the faults across bitcoin and litecoin. Find a timeout that makes a party lose money.

```racket
(chain mainnet #:rules bitcoin)
(chain litenet #:rules litecoin)

(actor alice #:chains (litenet mainnet)
  #:fund ([on-ltc litenet (ltc 1)])      ; labelled starting coin
  (on (start)
      (lock-htlc #:from on-ltc #:to op #:secret s
                 #:timeout (blocks 144))
      (send op 'locked))
  (on (seen-htlc #:on mainnet #:to alice) (claim #:reveal s)))

(actor op #:chains (litenet mainnet)
  #:fund ([on-btc mainnet (btc 1)])
  (on (msg 'locked)
      (lock-htlc #:from on-btc #:to alice
                 #:hash (hash-of s) #:timeout (blocks 72)))
  (on (seen-preimage s) (claim #:on litenet)))

(explore #:interleavings 500 #:seed 3
  #:faults (list (offline op #:after 'locked)
                 (delay-msgs (uniform 0 2 h)))
  #:invariant (no-loss op))
; => (counterexample
;     #:why (timeout-order litenet 144 blocks = 6 h
;            < mainnet 72 blocks = 12 h)
;     #:schedule <id>)
```

## Why this scenario is important

You must compare timeouts in wall time across chains with different block intervals. On litecoin, 144 blocks end after 6 hours, and 72 blocks on bitcoin end after 12 hours. [Scenario 5](5-litecoin-swap.md) shows this order by hand. In this scenario, `explore` finds it as a counterexample. Then the agent changes the timeouts until `explore` finds no counterexample.

**This scenario will need these items:**

- `actor` with `on` handlers and `send`.
- Chain events, for example `seen-htlc` and `seen-preimage`.
- A deterministic scheduler across the clocks of all chains, from the shared clock of Scenario 5.
- `explore`, fault injection and invariants.
- Counterexample schedules that you can replay.

Chains with different rules in one session ([Scenario 4](4-ctv.md)) and HTLCs ([Scenario 2](2-htlc.md)) are available now. Litecoin and the shared clock come with [Scenario 5](5-litecoin-swap.md).
