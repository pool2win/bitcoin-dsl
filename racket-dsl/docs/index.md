# Bitcoin DSL

The Bitcoin DSL is a language for Bitcoin systems and new Bitcoin ideas. With it, you describe chains, transactions, scripts, covenants and soft-fork proposals. You can check each result against real Bitcoin nodes.

## Use it through an agent

The primary method is to talk to an AI agent, for example Claude Code. The agent uses the DSL through its [MCP server](guides/mcp.md). You give the goal in your words. The agent writes the DSL code, runs it and gives you the results. This is an example session:

```text
You:    Give Alice a mature coin, pay Bob 49.99 BTC with 0.009 BTC change, and confirm it.
        Show the fee. Then check the session against a real node.

Agent → describe                       ; learns the forms
Agent → eval
          (chain mainnet #:rules bitcoin)
          (keys alice bob)
          (define cb (first (mine 1 #:on mainnet #:to alice)))
          (try (spend cb #:sign alice #:outputs (list (output 'b (wpkh bob) (btc 49.99)))))
      ← (rejected #:chain mainnet #:rule coinbase-maturity #:input 0 #:need 100 #:have 1 #:step 3 #:trace 1)

Agent → eval
          (void (mine 100 #:on mainnet))
          (define-tx pay
            #:inputs  ([cb #:sign alice])
            #:outputs ([to-bob (wpkh bob) (btc 49.99)] [change (wpkh alice) (btc 0.009)]))
          (confirm pay)
          (fee pay)
      ← (accepted #:chain mainnet #:tx #<tx pay 20a17961> #:step 5 #:trace 2)
        (btc 0.001)

Agent → eval
          (summary (replay (scenario-log) #:targets (hash 'mainnet (regtest))))
      ← ((confirmed 6) (disagree 0) (unverified 0))

Agent:  The first spend was too early: a coinbase must be 100 blocks deep, and the coin
        was 1 block deep. After 100 more blocks, the payment is confirmed with a fee of
        0.001 BTC. A regtest Bitcoin Core node agrees with all 6 steps.
```

To start, read [Use the MCP server](guides/mcp.md). To learn how agents operate the DSL, read [How agents use the DSL](guides/agents.md).

## Write the code yourself

The DSL is a Racket language, thus a Lisp. If you prefer to write the code manually, write it as a Racket module. This is the same payment:

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

To start, read [Get started](getting-started.md) and [Write scenarios by hand](guides/scenarios-by-hand.md).

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

- To use the DSL through an agent, read [Use the MCP server](guides/mcp.md).
- To learn how agents operate the DSL, read [How agents use the DSL](guides/agents.md).
- To write Racket directly, read [Get started](getting-started.md), then [Write scenarios by hand](guides/scenarios-by-hand.md).
- To find a form or a rule, read [Forms](reference/forms.md), [Results and traces](reference/results.md) and [Consensus rules](reference/rules.md).
