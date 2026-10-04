# Bitcoin DSL

A Racket language for describing Bitcoin systems and exploring new ideas: chains, transactions, scripts, covenants and soft-fork proposals. It is built to be driven by AI agents over [MCP](guides/mcp.md), and every result can be checked against real Bitcoin nodes.

```racket
#lang bitcoin/model
(chain mainnet #:rules bitcoin)
(keys alice bob)

(define cb (first (mine 1 #:on mainnet #:to alice)))
(void (mine 100 #:on mainnet))

(define-tx pay
  #:inputs  ([cb #:sign alice])
  #:outputs ([to-bob (wpkh bob) (btc 49.99)]
             [change (wpkh alice) (btc 0.009)]))

(confirm pay)                ; => (accepted #:chain mainnet #:tx #<tx pay …> #:step 4 #:trace 1)
(utxos #:spendable-by bob)   ; => (list to-bob)
(fee pay)                    ; => (btc 0.001)
```

## Two layers

**The model** is a custom consensus engine. Consensus is a *value*: an ordered list of named rules, an opcode table and a sighash selector per spend version. Crypto is symbolic: a key is a name and a signature carries the exact list of fields it commits to. Every rejection names the rule that failed, and `explain` shows each rule and opcode that ran. Because rule sets are values, a soft fork is a small diff:

```racket
(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))
(diff-consensus bitcoin ctv-rules)   ; => ((opcode #xb3 nop4 -> ctv))
```

**Conformance** lowers a model session to real keys, signatures and transaction bytes, and replays it step by step against throwaway regtest nodes (Bitcoin Core, or Bitcoin Inquisition for CTV). Each step comes back `confirmed`, `disagree` or `unverified`. Nothing passes silently.

```racket
#lang bitcoin/conform
(summary (replay (scenario-log) #:targets (hash 'mainnet (regtest))))
; => ((confirmed 5) (disagree 0) (unverified 0))
```

## What is built

| Area | Status |
|---|---|
| Fund and spend, P2WPKH, P2WSH, taproot key and script paths | done ([Scenario 1](scenarios/1-fund-and-spend.md)) |
| Contracts with spend paths, CSV/CLTV/BIP68 timelocks, explained failures, snapshots | done ([Scenario 2](scenarios/2-htlc.md)) |
| All BIP143 and BIP341 sighash flags, `commits`, `free-fields`, `mutate`, `sighash-search` | done ([Scenario 3](scenarios/3-sighash.md)) |
| Consensus composition, CTV, `diff-consensus`, `audit`, several chains | done ([Scenario 4](scenarios/4-ctv.md)) |
| Replay against Core and Inquisition, `sighash-matrix` | done ([Scenario 7](scenarios/7-conformance.md)) |
| Share chains (p2poolv2) | planned ([Scenario 5](scenarios/5-share-chain.md)) |
| Actors, cross-chain swaps, fault exploration | planned ([Scenario 6](scenarios/6-swap.md)) |

## Where to go next

- **Using it with Claude Code:** [Using it over MCP](guides/mcp.md).
- **Understanding how agents drive it:** [How agents use it](guides/agents.md).
- **Writing Racket directly:** [Getting started](getting-started.md), then [Writing scenarios by hand](guides/scenarios-by-hand.md).
- **Looking something up:** [Forms](reference/forms.md), [Results and traces](reference/results.md), [Consensus rules](reference/rules.md).
