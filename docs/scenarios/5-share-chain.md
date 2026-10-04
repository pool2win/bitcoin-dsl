# Scenario 5: p2poolv2 share chain with bitcoin

!!! note "Planned for v2"
    This scenario has a design, but it is not built. The code below shows the proposed syntax. You cannot run it yet.

**Goal:** Model a share chain with rules that are different from bitcoin for difficulty, uncles and payouts. Link it to a parent bitcoin chain. Then check the payouts and the uncles under latency.

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

The parameter values (`share-spacing`, `hl` and `w`) are temporary. The real p2poolv2 settings will replace them.

## Why this scenario is important

The consensus of p2poolv2 is not a fork of bitcoind. It has a share chain with ASERT difficulty, uncles, PPLNS payouts and MuHash commitments. Thus no binary is available for a conformance check. This scenario needs consensus as a value. A share chain is a different type of chain. It has a parent and its own rules. When a share meets the target of the parent, the engine will make a bitcoin block. The coinbase of that block pays the PPLNS split.

An agent will learn how changes to the rules change the payouts and their variance. Examples of such changes are the window, the uncle split and the difficulty adjustment. The agent will not need real nodes.

**This scenario will need these items:**

- Types of chains other than transaction chains, and the `#:parent` link.
- `miners` with a seeded hashrate, and `network` latency.
- Simulated time, `run`, and `repeat` with statistics.
- `check` and payout queries.
