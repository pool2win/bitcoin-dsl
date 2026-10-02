# Racket Bitcoin DSL: Example Agent Scenarios

Oct 1, 2026 · @Kulpreet Singh

## Purpose and conventions

Seven scenarios an agent should be able to run over an MCP session; the forms they need define v0 of the DSL. Each scenario lists its goal, the DSL code, what the agent learns, and the features it forces. All syntax is a proposal to argue with.

Conventions used throughout:

- `#lang bitcoin/model` runs against the custom consensus engine. Crypto is symbolic: a signature is a value `(sig key commitment)`, verified by recomputing the commitment.
- Every chain is declared with a consensus value: `(chain mainnet #:rules bitcoin)`. Rules are composable with `define-consensus` and `#:extends`.
- Amounts are explicit: `(btc 49.99)` or `(sats 1000)`. Fee is inputs minus outputs unless set.
- Every query returns data, never prints. Results the agent branches on have a fixed shape:

```racket
(accepted #:tx t #:step 12)
(rejected #:rule csv #:input 0
          #:need 144 #:have 1
          #:trace <trace-id>)
(unverified #:reason (model-only-rule ctv))
```

- `#:rule` names come from the consensus value, so `explain` and `diff-consensus` can point back to the exact rule.
- The MCP session exposes `eval`, `snapshot`, `restore`, `explain` and `describe`. Scenarios below are what the agent sends through `eval`.

Coins are never picked implicitly. Every coin comes from `mine` (which always returns a list of the coinbase coins it mined) or from a labeled transaction output:

- `define-tx` is a definition form. Each output label is a bare identifier, bound as a variable to that output's coin.
- `spend` is an expression. It takes `(output 'label lock amount)` values, stores the labels as data, and `(out tx 'label)` looks one up. Use it for one-off `try` calls and REPL evals.
- `utxos` is an explicit query (`#:spendable-by`, `#:locked-by`) returning coins in a fixed order: confirmation height, then outpoint.

## Scenario 1: Fund and spend on one chain

Goal: the smallest end-to-end loop. Mine to Alice, pay Bob, confirm, query state.

```racket
#lang bitcoin/model
(chain mainnet #:rules bitcoin)
(keys alice bob)

(define cb (first (mine 1 #:on mainnet #:to alice)))  ; mine returns a list of coinbase coins
(mine 100 #:on mainnet)                               ; mature it

(define-tx pay
  #:inputs  ([cb #:sign alice])
  #:outputs ([to-bob (wpkh bob)   (btc 49.99)]
             [change (wpkh alice) (btc 0.009)]))
; binds pay, to-bob = (output-of pay 0), change = (output-of pay 1)

(broadcast pay)
(mine 1 #:on mainnet)

(confirmed? pay)                 ; => #t
(utxos #:spendable-by bob)       ; => (list to-bob)
(fee pay)                        ; => (btc 0.001)
(equal? to-bob (out pay 'to-bob)) ; => #t
```

The agent learns the basic vocabulary and that results are values it can inspect.

Forces: `chain`, `keys`, `mine` returning coins, `define-tx`, `output-of`, `out`, `broadcast`, `confirmed?`, `utxos`, `fee`, output templates (`wpkh`), symbolic signing, coinbase maturity rule.

## Scenario 2: HTLC branches, timelocks and explained failures

Goal: define a contract, enumerate its spend paths, try one too early, read why it failed, then fork the state to try both paths.

```racket
(contract htlc (sender receiver secret timeout)
  (or (and (pk receiver) (sha256 secret))
      (and (pk sender) (older timeout))))

(define s (secret 's1))
(define cb (first (mine 1 #:on mainnet #:to alice)))
(mine 100 #:on mainnet)

(define-tx fund
  #:inputs  ([cb #:sign alice])
  #:outputs ([locked (htlc alice bob s 144) (btc 49.99)]))
(confirm fund)

(branches locked)
; => ((claim  #:needs ((sig bob) (preimage s)))
;     (refund #:needs ((sig alice) (age>= 144))))

(define refund
  (spend locked #:path 'refund #:sign alice
    #:outputs (list (output 'back (wpkh alice) (btc 49.98)))))
(try refund)
; => (rejected #:rule csv #:input 0 #:need 144 #:have 1 ...)
(explain (last-trace))   ; opcode-level steps + stacks

(define t0 (snapshot))
(mine 143 #:on mainnet)
(try refund)             ; => (accepted ...)
(restore t0)
(try (spend locked #:path 'claim #:sign bob #:reveal s
       #:outputs (list (output 'claimed (wpkh bob) (btc 49.98)))))
; => (accepted ...)
```

The agent learns to reason in branches, not single paths. `#:path` sets nSequence and picks the witness automatically, as `csv:` did in the Ruby DSL.

Forces: `contract` with a small policy language (`pk`, `sha256`, `older`, `after`, `and`, `or`, `thresh`), `secret`, `branches`, `try`, `explain`, `snapshot`, `restore`, relative timelocks, structured rejections.

## Scenario 3: Sighash exploration and fee bumping

Goal: find which sighash flags let Carol add a fee input to Alice's signed payment without breaking Alice's signature.

```racket
(define cb (first (mine 1 #:on mainnet #:to alice)))
(define cc (first (mine 1 #:on mainnet #:to carol)))
(mine 100 #:on mainnet)

(define-tx split                ; give carol a small fee coin
  #:inputs  ([cc #:sign carol])
  #:outputs ([fee-coin (wpkh carol) (btc 0.01)]
             [rest     (wpkh carol) (btc 49.98)]))
(confirm split)

(define-tx pay
  #:inputs  ([cb #:sign alice #:sighash '(all anyonecanpay)])
  #:outputs ([to-bob (wpkh bob) (btc 49.99)]))

(commits (sig-of pay 0))
; => (version locktime (input 0 outpoint sequence)
;     (prevout 0 amount spk) (outputs all))

(free-fields pay)
; => ((inputs append) (inputs remove-others))

(define bumped (add-input pay fee-coin #:sign carol))
(try bumped)                         ; => (accepted ...)
(mutate pay '(output to-bob amount) (btc 49.0))
; => (breaks ((sig alice 0 #:field (outputs all))))

(sighash-search pay
  #:goal  (can (add-input))
  #:keep  (fixed (outputs all))
  #:over  '(wpkh tr-key tr-script))
; => table of flag sets x spend types that satisfy the goal
```

The agent learns what each signature commits to and can search for the weakest commitment that still meets a goal. The selector differs per spend version (legacy, BIP143, BIP341), so `#:over` compares them directly.

Forces: `#:sighash`, `sig-of`, `commits`, `free-fields`, `mutate`, `add-input`, `sighash-search`, per-version sighash selectors in the consensus value, taproot key and script spends.

## Scenario 4: CTV vault on two chains with different rules

Goal: run the same covenant on a chain with CTV and one without, and catch that it is silently unenforced where the opcode is still NOP4.

```racket
(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))

(chain mainnet #:rules bitcoin)
(chain signet #:rules ctv-rules)
(keys alice cold mallory)
(diff-consensus bitcoin ctv-rules)
; => ((opcode #xb3 nop4 -> ctv))

(define tmpl
  (template #:outputs (list (output 'to-cold (wpkh cold) (btc 49.98)))))
(contract vault () (ctv tmpl))

(for/list ([ch (list mainnet signet)])
  (define cb (first (mine 1 #:on ch #:to alice)))
  (mine 100 #:on ch)
  (define-tx lock
    #:inputs  ([cb #:sign alice])
    #:outputs ([vaulted (vault) (btc 49.99)]))
  (confirm lock)
  (try (spend vaulted            ; thief ignores the template
         #:outputs (list (output 'stolen (wpkh mallory) (btc 49.98))))))
; => ((accepted #:chain mainnet ...)                 ; covenant unenforced
;     (rejected #:chain signet #:rule ctv-template-mismatch ...))

(audit (vault) #:on mainnet)
; => (warning #:rule-unenforced ctv #:chain mainnet)
```

The agent learns that a contract's safety is relative to a rule set, and gets a warning before trusting it. This is the pattern for any soft-fork proposal: CAT, CSFS, TXHASH, or a new sighash mode.

Forces: `define-consensus`, `#:extends`, opcode upgrades, `diff-consensus`, multiple chains in one session, `template`, `audit`, rejections tagged with chain.

## Scenario 5: p2poolv2 share chain alongside bitcoin

Goal: model a share chain whose rules differ from bitcoin's in difficulty, uncles and payouts, linked to a parent bitcoin chain. Then check payouts and uncle handling under latency.

```racket
(define-consensus p2poolv2-share
  #:kind    share-chain
  #:parent  bitcoin
  #:pow     (asert #:spacing share-spacing #:half-life hl)
  #:uncles  (max 3 #:split 90/10)
  #:payout  (pplns #:window w)
  #:commit  muhash)

(chain mainnet   #:rules bitcoin)
(chain share #:rules p2poolv2-share #:parent mainnet)

(miners #:on share #:seed 7
  (m1 #:hashrate 30%)
  (m2 #:hashrate 70%))
(network #:latency (uniform 50 400 ms))

(run #:until (blocks 10 #:on mainnet))

(uncles share)               ; shares included as uncles, by miner
(payouts mainnet #:to '(m1 m2))  ; sums across found bitcoin blocks
(check (within 5% (share-of m1 (payouts mainnet)) 30%))

(repeat 200 #:vary seed (payouts mainnet #:to 'm1))  ; variance
```

Parameter values (`share-spacing`, `hl`, `w`) are placeholders, to be filled from the real p2poolv2 settings.

The agent learns how rule changes (window, uncle split, DAA) shift payouts and variance, without running real nodes. When a share meets the parent target, the engine produces a bitcoin block whose coinbase pays the PPLNS split.

Forces: chain kinds beyond tx chains, `#:parent` linkage, `miners` with seeded hashrate, `network` latency, simulated time, `run`, `repeat` with statistics, `check`, payout queries.

## Scenario 6: Cross-chain swap with actors and faults

Goal: an operator swaps Alice's coins on a fast side chain for bitcoin. Explore interleavings and faults, and find a timeout choice that loses Alice money.

```racket
(define-consensus side-rules #:extends bitcoin
  #:pow (fixed-spacing 60 s))
(chain mainnet  #:rules bitcoin)
(chain side #:rules side-rules)

(actor alice #:chains (side mainnet)
  #:fund ([on-side side (btc 1)])     ; labeled starting coin
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

The agent learns that timeouts must be compared in wall time across chains with different block spacing, then tunes them until `explore` finds no counterexample.

Forces: `actor`, `on` handlers, `send`, chain events (`seen-htlc`, `seen-preimage`), a deterministic scheduler over all chains' clocks, `explore`, fault injection, invariants, replayable counterexample schedules.

## Scenario 7: Conformance replay against regtest

Goal: take a scenario the agent is happy with in the model, lower it to real keys, signatures and tx bytes, and replay it against real nodes step by step.

```racket
#lang bitcoin/conform
(define run1
  (replay (scenario-log 'htlc-refund)
          #:targets (hash 'mainnet (regtest #:build 'core)
                          'signet (regtest #:build 'inquisition))))

(summary run1)
; => ((confirmed 14) (disagree 0) (unverified 0))

(sighash-matrix
  #:spend-types '(legacy wpkh tr-key tr-script)
  #:flags       all-flag-combinations
  #:target      (regtest #:build 'core))
; for each cell: mutate every field the model calls free
; (node must accept) and every committed field (node must reject)
; => ((disagree #:type legacy #:flags (single)
;               #:field (output out-of-range) ...))
```

The agent learns which model results are backed by a real node. Steps using rules no build implements come back `unverified`, never silently confirmed. A disagreement is a model bug or an idea that depends on rules that don't exist.

Forces: a scenario log format shared by both layers, `lower` (symbolic to real signatures with BIP143/BIP341 digests), `replay`, per-step status, `sighash-matrix`, node targets by build. The same harness doubles as a differential fuzzer.

## Derived v0 definition

v0 is the forms needed by Scenarios 1 to 3, plus the scenario log and enough conformance to replay Scenario 1. Everything else waits until a scenario forces it.

| Area | Forms | Scenarios | In v0 |
| --- | --- | --- | --- |
| Values | `keys`, `btc`, `sats`, `secret`, coins returned by `mine`, `output-of`, `out`, `utxos`, output templates (`wpkh`, `tr`) | 1, 2, 3 | Yes |
| Transactions | `define-tx`, `spend`, `output`, `add-input`, `broadcast`, `confirm`, `fee`, `#:path`, `#:sighash` | 1, 2, 3 | Yes |
| Contracts | `contract`, policy ops (`pk`, `sha256`, `older`, `after`, `and`, `or`, `thresh`), `branches` | 2 | Yes |
| Consensus | one fixed `bitcoin` rule set with named rules and trace hooks | 1, 2, 3 | Yes |
| Execution | `chain`, `mine`, `try`, `confirmed?`, result shapes | 1, 2 | Yes |
| Sighash | `sig-of`, `commits`, `free-fields`, `mutate` | 3 | Yes |
| Session / MCP | `eval`, `snapshot`, `restore`, `explain`, `describe` | 2 | Yes |
| Scenario log | s-expression event log written by every run | 7 | Yes |
| Conformance | `lower`, `replay` for P2WPKH only | 7 | Yes |
| Sighash search | `sighash-search`, `sighash-matrix` | 3, 7 | v1 |
| Rule composition | `define-consensus`, `#:extends`, `diff-consensus`, `audit`, `template` | 4 | v1 |
| Other chain kinds | share chains, `#:parent`, `miners`, `network`, `run`, `repeat` | 5 | v2 |
| Actors | `actor` with `#:fund`, `on`, `send`, scheduler, `explore`, faults, invariants | 6 | v3 |

The one structural decision v0 must get right even though it uses one rule set: rules are named values with trace hooks, not code inside an interpreter loop. Otherwise Scenario 4's `diff-consensus` and Scenario 5's share chain become a rewrite.

## Build order and open questions

Build order, each step ending with a scenario that runs end to end:

1. Core values and the rule-set representation (named rules, trace hooks). Done when Scenario 1 runs in the model.
2. Policy language, `branches`, `try`, `explain`, `snapshot`/`restore`. Done when Scenario 2 runs.
3. Per-version sighash selectors and the sighash queries. Done when Scenario 3 runs.
4. Scenario log, `lower` and `replay` for P2WPKH against regtest Core. Done when Scenario 1 replays with zero disagreements.
5. MCP server wrapping a persistent session. Done when an agent completes Scenarios 1 to 3 without human help.
6. v1 to v3 as in the table above, in scenario order.

Open questions:

- [ ] Scenario log format: plain s-expressions, or a typed schema that agents and the replayer both validate?
- [ ] How much of the policy language to borrow from miniscript, and whether to compile through rust-miniscript for conformance.
- [ ] Real p2poolv2 parameter values for Scenario 5, and whether conformance for the share chain runs against local p2poolv2 nodes.
- [ ] Does `explore` enumerate interleavings exhaustively for small cases, or only sample by seed?
- [ ] Legacy sighash quirks (FindAndDelete, codesep): model them, or mark unsupported until a scenario needs them?
