# Scenario 6: Cross-chain swap with actors and faults

!!! note "Planned for v3"
    This scenario is designed but not built. The code below is the proposed syntax, not something you can run yet.

**Goal:** an operator swaps Alice's coins on a fast side chain for bitcoin. Explore interleavings and faults, and find a timeout choice that loses Alice money.

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

## Why it matters

Timeouts have to be compared in wall time across chains with different block spacing: 144 blocks on a one-minute chain expire long before 72 blocks on bitcoin. An agent will learn that from a counterexample, then tune the timeouts until `explore` finds none.

**Will need:** `actor` with `on` handlers and `send`, chain events (`seen-htlc`, `seen-preimage`), a deterministic scheduler over all chains' clocks, `explore`, fault injection, invariants, and replayable counterexample schedules. Chains with different rules in one session ([Scenario 4](4-ctv.md)) and HTLCs ([Scenario 2](2-htlc.md)) already exist.
