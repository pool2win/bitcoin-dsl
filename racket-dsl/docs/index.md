# Bitcoin DSL

The Bitcoin DSL is a Racket language for Bitcoin systems and new Bitcoin ideas. With it, you describe chains, transactions, scripts, covenants and soft-fork proposals. AI agents use it through [MCP](guides/mcp.md). You can check each result against real Bitcoin nodes.

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

## The two layers

**The model** is a consensus engine for exploration. Consensus is a value: a list of named rules, a table of opcodes and a sighash selector for each spend version. The crypto is symbolic. A key is a name, and a signature contains the fields that it commits to. Each rejection gives the name of the rule that failed. `explain` shows each rule and each opcode that ran. Because rule sets are values, a soft fork is a small change:

```racket
(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))
(diff-consensus bitcoin ctv-rules)   ; => ((opcode #xb3 nop4 -> ctv))
```

**Conformance** lowers a session to real keys, signatures and transaction bytes. Then it replays the session, step by step, against temporary regtest nodes. These nodes are Bitcoin Core, or Bitcoin Inquisition for CTV. Each step gets the status `confirmed`, `disagree` or `unverified`. No step passes without a check.

```racket
#lang bitcoin/conform
(summary (replay (scenario-log) #:targets (hash 'mainnet (regtest))))
; => ((confirmed 5) (disagree 0) (unverified 0))
```

## Status

| Area | Status |
|---|---|
| Fund and spend; P2WPKH, P2WSH and taproot key and script paths | Done ([Scenario 1](scenarios/1-fund-and-spend.md)) |
| Contracts with spend paths, CSV, CLTV and BIP68 timelocks, explained failures, snapshots | Done ([Scenario 2](scenarios/2-htlc.md)) |
| All BIP143 and BIP341 sighash flags, `commits`, `free-fields`, `mutate`, `sighash-search` | Done ([Scenario 3](scenarios/3-sighash.md)) |
| Composition of rule sets, CTV, `diff-consensus`, `audit`, more than one chain | Done ([Scenario 4](scenarios/4-ctv.md)) |
| Replay against Core and Inquisition, `sighash-matrix` | Done ([Scenario 7](scenarios/7-conformance.md)) |
| Share chains (p2poolv2) | Planned ([Scenario 5](scenarios/5-share-chain.md)) |
| Actors, swaps between chains, exploration of faults | Planned ([Scenario 6](scenarios/6-swap.md)) |

## Where to go next

- To use the DSL with Claude Code, read [Use the MCP server](guides/mcp.md).
- To learn how agents operate the DSL, read [How agents use the DSL](guides/agents.md).
- To write Racket directly, read [Get started](getting-started.md), then [Write scenarios by hand](guides/scenarios-by-hand.md).
- To find a form or a rule, read [Forms](reference/forms.md), [Results and traces](reference/results.md) and [Consensus rules](reference/rules.md).
