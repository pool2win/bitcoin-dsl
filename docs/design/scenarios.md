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
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(define s (secret 's1))
(define cb (first (mine 1 #:on mainnet #:to alice)))
(mine 100 #:on mainnet)

(define-tx fund
  #:inputs  ([cb #:sign alice])
  #:outputs ([locked (htlc alice bob s 144) (btc 49.99)]))
(confirm fund)

(branches locked)
; => ((claim  #:needs ((sig bob) (preimage s1)))
;     (refund #:needs ((sig alice) (age>= 144))))

(define refund
  (spend locked #:path 'refund #:sign alice
    #:outputs (list (output 'back (wpkh alice) (btc 49.98)))))
(try refund)
; => (rejected #:rule sequence-lock #:input 0 #:need 144 #:have 1 ...)
(explain (last-trace))   ; rule and opcode steps, with stacks

(define t0 (snapshot))
(mine 143 #:on mainnet)
(try refund)             ; => (accepted ...)
(restore t0)
(try (spend locked #:path 'claim #:sign bob #:reveal s
       #:outputs (list (output 'claimed (wpkh bob) (btc 49.98)))))
; => (accepted ...)
```

The agent learns to reason in branches, not single paths. An `or` arm may carry a label (`[claim ...]`), which names the spend path; unlabelled arms are named by position (`0`, `1`, ...), nested labels join with `/`, and `thresh` paths are named by their keys (`alice+bob`). `#:path` sets nSequence (and nLockTime for `after`) and fills the witness automatically, as `csv:` did in the Ruby DSL.

The early refund fails BIP68's `sequence-lock` rule, not the `csv` opcode: `#:path 'refund` sets nSequence to 144, so OP_CSV passes and the input's relative lock is what is not yet met. This matches what a real node reports (`non-BIP68-final`). The `csv` opcode rejects when nSequence itself is wrong, e.g. relative locks disabled.

Forces: `contract` with a small policy language (`pk`, `sha256`, `older`, `after`, `and`, `or`, `thresh`), `secret`, `branches`, `try`, `explain`, `snapshot`, `restore`, relative and absolute timelocks (BIP65, BIP68, BIP112), P2WSH, structured rejections.

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
; => (version (own-input outpoint) (own-prevout script) (own-prevout amount)
;     (own-input sequence) (outputs all) locktime)

(free-fields pay)
; => ((inputs append) (inputs remove-others))

(define bumped (add-input pay fee-coin #:sign carol))
(try bumped)                         ; => (accepted ...)
(mutate pay '(output to-bob amount) (btc 49.0))
; => (breaks ((sig alice 0 #:fields ((outputs all)))))

(sighash-search pay
  #:goal  (can (add-input))
  #:keep  (fixed (outputs all))
  #:over  '(wpkh tr-key tr-script))
; => table of flag sets x spend types that satisfy the goal
```

The agent learns what each signature commits to and can search for the weakest commitment that still meets a goal. The selector differs per spend version (legacy, BIP143, BIP341), so `#:over` compares them directly.

Field names are relative to the signing input (`own-input`, `own-prevout`, `own-output`) because the digest binds the input's outpoint, not its position: under ANYONECANPAY the input can move. `mutate` and `free-fields` do not reason about flags; they edit the tx and recompute each signature's commitment with the selector verification uses, so they cannot disagree with it. `free-fields` checks a fixed catalogue of edits: `(inputs append)`, `(inputs remove-others)`, `(outputs append)`, each output's amount and lock, each input's sequence, `version` and `locktime`.

Taproot outputs are `(tr key)` for key-path only, or `(tr key #:leaves (list (htlc ...) ...))` with leaves built by `contract`. Branches are named `key` for the key path and after each leaf's contract (`htlc/claim`, or `single-key-1` when two leaves share a contract). A taproot signature's `commits` differs from BIP143: it commits to every input's amount and scriptPubKey, to all sequences whenever not ANYONECANPAY, to the input's index rather than its outpoint, to the spend type, and for a script path to the leaf.

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
; => ((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))
```

The agent learns that a contract's safety is relative to a rule set, and gets a warning before trusting it. This is the pattern for any soft-fork proposal: CAT, CSFS, TXHASH, or a new sighash mode.

Forces: `define-consensus`, `#:extends`, opcode upgrades, `diff-consensus`, multiple chains in one session, `template`, `audit`, rejections tagged with chain.

As built (v1): opcodes are identified by byte, so the script's `ctv` runs as NOP4 on mainnet (`explain` shows `#:as nop4`). `define-consensus` also takes `#:rules (add r) (remove n) (replace n r)`, `#:params (set k v)` and `#:sighash (add version selector)`. A template mismatch names the fields that differ (`#:fields ((outputs all))`), and `audit` returns a list of warnings, `'()` when clean. The test also checks an honest template-matching spend on both chains, so a broken lowering cannot hide behind the thief's rejection. Replayed with mainnet on Core and signet on Bitcoin Inquisition, all 14 steps are confirmed; with signet on Core, the two CTV-executing spends come back `(unverified #:reason (model-only-rule ctv))`.

## Scenario 5: Litecoin alongside bitcoin, and an atomic swap between them

Goal: run a second real chain with different consensus parameters next to bitcoin, then build a contract that spans both: an atomic swap of Alice's LTC for Bob's BTC. Drive it step by step on one shared clock, show that the timeouts must be compared in wall time, and show the losing order of events when they are not.

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
; => ()   the initiator's refund opens after the participant's

;; Alice claims the BTC, which reveals s on mainnet; Bob reads it and claims the LTC.
(define claim-btc (spend on-btc #:path 'claim #:sign alice #:reveal s
                    #:outputs (list (output 'a (wpkh alice) (btc 49.98)))))
(confirm claim-btc)
(revealed claim-btc)                      ; => (list s)
(confirm (spend on-ltc #:path 'claim #:sign bob #:reveal s
           #:outputs (list (output 'b (wpkh bob) (ltc 49.98)))))

;; The broken variant: Alice's LTC lock is 144 ltc blocks = 6 h, shorter than
;; Bob's 12 h. swap-check warns, and the losing order is reproducible:
;; after 6 h Alice refunds her LTC, then still claims Bob's BTC before 12 h.
; (swap-check ...) => ((warning #:initiator-refund-first (hours 6) #:participant-refund (hours 12)))

(replay (scenario-log) #:targets (hash 'mainnet (regtest)
                                       'litenet (regtest #:build 'litecoin)))
```

The agent learns that a contract across chains is only as safe as the ordering of its timeouts in wall time, that block counts on chains with different spacing are not comparable, and that a secret revealed on one chain is visible to the other party. These are the contracts we devise and check between bitcoin and litecoin first, before automating the search in Scenario 6.

Forces: a built-in `litecoin` consensus value (bitcoin's script, segwit, taproot and sighash; 150-second blocks; 84M max money; litecoin regtest parameters), an `ltc` amount constructor and per-chain units, a shared simulated clock (`advance`, `hours`, `now`, wall-time conversion of block counts), `refund-times` and `swap-check` for cross-chain timeout ordering, `revealed` to read preimages from a spend, replay against a Litecoin Core regtest node.

## Scenario 6: Cross-chain swap with actors and faults

Goal: the swap of Scenario 5, but driven by actors instead of by hand. Explore interleavings and faults across bitcoin and litecoin, and find a timeout choice that loses money.

```racket
(chain mainnet #:rules bitcoin)
(chain litenet #:rules litecoin)

(actor alice #:chains (litenet mainnet)
  #:fund ([on-ltc litenet (ltc 1)])     ; labeled starting coin
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

The agent learns to let `explore` find the bad orderings that Scenario 5 shows by hand, then tunes the timeouts until `explore` finds no counterexample.

Forces: `actor`, `on` handlers, `send`, chain events (`seen-htlc`, `seen-preimage`), a deterministic scheduler over all chains' clocks (built on Scenario 5's shared clock), `explore`, fault injection, invariants, replayable counterexample schedules.

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
  #:flags       'all
  #:target      (regtest #:build 'core))
; for each cell: try the tx unedited and under every edit,
; and check the model's verdict against the node
; => ((confirmed #:type wpkh #:flags (all) #:edit (inputs append)
;                #:model (rejected eval-false))
;     ...
;     (unsupported #:type legacy))
```

The agent learns which model results are backed by a real node. Steps using rules no build implements come back `unverified`, never silently confirmed. A disagreement is a model bug or an idea that depends on rules that don't exist.

Forces: a scenario log format shared by both layers, `lower` (symbolic to real signatures with BIP143/BIP341 digests), `replay`, per-step status, `sighash-matrix`, node targets by build. The same harness doubles as a differential fuzzer.

As built for v0: `(replay (scenario-log) #:targets (hash 'mainnet (regtest)))` starts a fresh regtest node per chain in a temporary datadir and stops it afterwards. A model signature is lowered by signing the BIP143 digest of the fields it committed to, so a signature that is invalid in the model stays invalid on the node. The node runs with standardness and fee floors relaxed, and RPC calls pass `maxfeerate=0`, so disagreements are about consensus. Taproot is lowered too (BIP340 Schnorr, TapTweak, control blocks, BIP341 digest).

As built for v1: each target declares the consensus it runs (`core` runs `bitcoin`; `inquisition` runs bitcoin with CTV, found via `BITCOIN_INQUISITION` or `~/projects/bitcoin-inquisition/build/bin/bitcoind`). Replay compares that with the chain's consensus and marks a step `unverified` when it exercised an opcode or rule that differs, rather than reading the node's answer as a verdict on the model's rule. When a mempool refuses a tx (e.g. NOP4 use is non-standard), the verdict comes from a block validity check (`generateblock` without submitting), and the mempool's reason is kept as `#:mempool-only`. `sighash-matrix` runs in a scratch session; all 260 `wpkh`/`tr-key`/`tr-script` cells agree with Core. Legacy spends are not modelled and come back `unsupported`.

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
| Sighash search | `sighash-search`, `sighash-matrix` | 3, 7 | v1 (done) |
| Rule composition | `define-consensus`, `#:extends`, `diff-consensus`, `audit`, `template` | 4 | v1 (done) |
| Second chain and cross-chain contracts | `litecoin`, `ltc`, shared clock (`advance`, `hours`, `now`), `refund-times`, `swap-check`, `revealed`, Litecoin Core replay target | 5 | v2 |
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

- [x] Scenario log format: typed. The log is a list of event values (`chain`, `mine` with per-block coinbase and included txs, `try`/`broadcast` with the exact tx and the model's verdict) holding the model values themselves. Serialising it to s-expressions is deferred until the MCP step needs it.
- [ ] How much of the policy language to borrow from miniscript, and whether to compile through rust-miniscript for conformance.
- [ ] Litecoin regtest specifics to verify against Litecoin Core: subsidy halving interval, coinbase maturity, whether taproot is active on regtest by default, and that `generatetodescriptor`/`generateblock` behave as in Core.
- [ ] MWEB (Litecoin's extension blocks): out of scope for v2; mark it unsupported. Revisit if a contract needs it.
- [ ] Amount units: amounts are base units on both chains; decide how results print LTC amounts (per-chain unit on coins and results, or a neutral unit).
- [ ] How `advance` mines: blocks in timestamp order across chains, each chain at its own spacing, so that cross-chain events interleave deterministically.
- [ ] Does `explore` enumerate interleavings exhaustively for small cases, or only sample by seed?
- [x] p2poolv2 share chain: replaced by Litecoin as the second chain (2026-10-09). Share chains may come back later; the p2poolv2 parameters found were 10 s share spacing, 600 s ASERT half-life, max 3 uncles at depth 3, uncle weight 9/10, PPLNS by `pplns_ttl_days = 7`.
- [ ] Legacy sighash quirks (FindAndDelete, codesep): model them, or mark unsupported until a scenario needs them?
