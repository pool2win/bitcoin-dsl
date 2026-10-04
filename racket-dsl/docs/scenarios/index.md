# Scenarios

Seven scenarios define what the DSL must do. Each one is something an agent should be able to run over an MCP session, and the forms they need defined each version of the language. Scenarios 1–4 and 7 run today; their pages include the exact code from the test suite. Scenarios 5 and 6 are designed but not built.

| # | Scenario | What it exercises | Status |
|---|---|---|---|
| 1 | [Fund and spend](1-fund-and-spend.md) | chains, keys, coins, `define-tx`, results as data | runs, replays |
| 2 | [HTLC and timelocks](2-htlc.md) | contracts, spend paths, CSV/BIP68, `explain`, snapshots | runs, replays |
| 3 | [Sighash and fee bumping](3-sighash.md) | sighash flags, `commits`, `free-fields`, `mutate`, `sighash-search` | runs, replays |
| 4 | [CTV on two chains](4-ctv.md) | `define-consensus`, CTV, `diff-consensus`, `audit` | runs, replays on Core + Inquisition |
| 5 | [p2poolv2 share chain](5-share-chain.md) | share chains, miners, latency, payouts | planned (v2) |
| 6 | [Cross-chain swap](6-swap.md) | actors, scheduling, faults, invariants | planned (v3) |
| 7 | [Conformance replay](7-conformance.md) | `replay`, targets, `sighash-matrix` | runs |

Every runnable scenario has a model test (`tests/scenario-N.rkt`) and a replay test (`tests/replay-N.rkt`) that checks it against real nodes.
