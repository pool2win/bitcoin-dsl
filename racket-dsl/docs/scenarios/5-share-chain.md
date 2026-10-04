# Scenario 5: p2poolv2 share chain alongside bitcoin

!!! note "Planned for v2"
    This scenario is designed but not built. The code below is the proposed syntax, not something you can run yet.

**Goal:** model a share chain whose rules differ from bitcoin's in difficulty, uncles and payouts, linked to a parent bitcoin chain. Then check payouts and uncle handling under latency.

```racket
(define-consensus p2poolv2-share
  #:kind    share-chain
  #:parent  bitcoin
  #:pow     (asert #:spacing share-spacing #:half-life hl)
  #:uncles  (max 3 #:split 90/10)
  #:payout  (pplns #:window w)
  #:commit  muhash)

(chain mainnet #:rules bitcoin)
(chain share   #:rules p2poolv2-share #:parent mainnet)

(miners #:on share #:seed 7
  (m1 #:hashrate 30%)
  (m2 #:hashrate 70%))
(network #:latency (uniform 50 400 ms))

(run #:until (blocks 10 #:on mainnet))

(uncles share)                     ; shares included as uncles, by miner
(payouts mainnet #:to '(m1 m2))    ; sums across found bitcoin blocks
(check (within 5% (share-of m1 (payouts mainnet)) 30%))

(repeat 200 #:vary seed (payouts mainnet #:to 'm1))  ; variance
```

The parameter values (`share-spacing`, `hl`, `w`) are placeholders, to be filled from the real p2poolv2 settings.

## Why it matters

p2poolv2's consensus (a share chain with ASERT difficulty, uncles, PPLNS payouts and MuHash commitments) is not a bitcoind fork, so there is no binary to point a conformance check at. This is the case that requires consensus to be a value: a share chain is a different *kind* of chain, linked to a parent, with its own rules. When a share meets the parent's target, the engine will produce a bitcoin block whose coinbase pays the PPLNS split.

An agent will learn how rule changes (window, uncle split, difficulty adjustment) shift payouts and variance, without running real nodes.

**Will need:** chain kinds beyond transaction chains, `#:parent` linkage, `miners` with seeded hashrate, `network` latency, simulated time, `run`, `repeat` with statistics, `check`, payout queries.
