# Scenario 6: Swap between chains, with actors and faults

!!! note "Planned for v3"
    This scenario has a design, but it is not built. The code below shows the proposed syntax. You cannot run it yet.

**Goal:** An operator swaps the coins of Alice on a fast side chain for bitcoin. Explore the orders of events and the faults. Find a timeout that makes Alice lose money.

```racket
(define-consensus side-rules #:extends bitcoin
  #:pow (fixed-spacing 60 s))
(chain mainnet #:rules bitcoin)
(chain side    #:rules side-rules)

(actor alice #:chains (side mainnet)
  #:fund ([on-side side (btc 1)])        ; labelled starting coin
  (on (start)
      (lock-htlc #:from on-side #:to op #:secret s
                 #:timeout (blocks 144))
      (send op 'locked))
  (on (seen-htlc #:on mainnet #:to alice) (claim #:reveal s)))

(actor op #:chains (side mainnet)
  #:fund ([on-btc mainnet (btc 1)])
  (on (msg 'locked)
      (lock-htlc #:from on-btc #:to alice
                 #:hash (hash-of s) #:timeout (blocks 72)))
  (on (seen-preimage s) (claim #:on side)))

(explore #:interleavings 500 #:seed 3
  #:faults (list (offline op #:after 'locked)
                 (delay-msgs (uniform 0 2 h)))
  #:invariant (no-loss alice))
; => (counterexample
;     #:why (timeout-order side 144 blocks = 2.4 h
;            < mainnet 72 blocks = 12 h)
;     #:schedule <id>)
```

## Why this scenario is important

You must compare timeouts in wall time across chains with different block intervals. On a chain with one block each minute, 144 blocks end much earlier than 72 blocks on bitcoin. An agent will learn this from a counterexample. Then it will change the timeouts until `explore` finds no counterexample.

**This scenario will need these items:**

- `actor` with `on` handlers and `send`.
- Chain events, for example `seen-htlc` and `seen-preimage`.
- A deterministic scheduler across the clocks of all chains.
- `explore`, fault injection and invariants.
- Counterexample schedules that you can replay.

Chains with different rules in one session ([Scenario 4](4-ctv.md)) and HTLCs ([Scenario 2](2-htlc.md)) are available now.
