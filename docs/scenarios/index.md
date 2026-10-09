# Scenarios

Seven scenarios define what the DSL must do. An agent must be able to run each scenario over an MCP session. The forms that the scenarios need define each version of the language. Scenarios 1 to 4 and 7 run now. Their pages include the exact code from the test suite. Scenarios 5 and 6 have a design, but they are not built.

| # | Scenario | Subjects | Status |
|---|---|---|---|
| 1 | [Fund and spend](1-fund-and-spend.md) | Chains, keys, coins, `define-tx`, results as data | Runs and replays |
| 2 | [HTLC and timelocks](2-htlc.md) | Contracts, spend paths, CSV and BIP68, `explain`, snapshots | Runs and replays |
| 3 | [Sighash and fee bumps](3-sighash.md) | Sighash flags, `commits`, `free-fields`, `mutate`, `sighash-search` | Runs and replays |
| 4 | [CTV on two chains](4-ctv.md) | `define-consensus`, CTV, `diff-consensus`, `audit` | Runs, and replays on Core and Inquisition |
| 5 | [Litecoin and an atomic swap](5-litecoin-swap.md) | A second real chain, one shared clock, contracts across chains | Planned (v2) |
| 6 | [Swap between chains with actors](6-swap.md) | Actors, schedules, faults, invariants on bitcoin and litecoin | Planned (v3) |
| 7 | [Conformance replay](7-conformance.md) | `replay`, targets, `sighash-matrix` | Runs |

Each scenario that runs has a model test (`tests/scenario-N.rkt`) and a replay test (`tests/replay-N.rkt`). The replay test checks the scenario against real nodes.
