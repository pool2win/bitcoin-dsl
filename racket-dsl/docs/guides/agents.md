# How agents use it

The DSL is designed for agents first: an agent with no prior knowledge should be able to connect to the [MCP server](mcp.md), learn the language from the server alone, and model a scenario end to end. This page explains the design choices that make that work and the workflow agents follow. It is also a guide for writing prompts and for building other agent integrations.

## Design for agents

**Self-description.** `describe` with no topic returns the purpose, conventions, tips, a complete worked example and every form with its usage string. Any form, rule, opcode, group or consensus name is a topic. The server's MCP `instructions` tell the agent to call `describe` first.

**Results are data.** Nothing prints; every query returns a value with a fixed shape that the agent can branch on:

```racket
(accepted #:chain mainnet #:tx #<tx pay 20a17961> #:step 4 #:trace 1)
(rejected #:chain mainnet #:rule sequence-lock #:input 0 #:need 144 #:have 1 #:step 9 #:trace 3)
```

**Every rejection names a rule.** The `#:rule` comes from the chain's consensus value, so `(describe 'sequence-lock)` documents it and `explain` on the `#:trace` id shows the exact rule and opcode steps that led there. Script failures name the specific failure (`eval-false`, `ctv-template-mismatch`) with a `#:cause` or `#:fields` saying why.

**Determinism.** Keys are derived from names, time is simulated, and results come in a fixed order (`utxos` by confirmation height, then outpoint). The same code gives the same txids every run, in the model and on the real node.

**Cheap branching.** `snapshot` and `restore` rewind chains and the scenario log, so an agent can try one spend path, rewind, and try another.

**Coins are explicit.** Coins come only from `mine` or from labelled outputs; nothing is picked implicitly, so an agent always knows which coin a transaction spends.

**Checked against reality.** `replay` lowers the session to real bytes and checks every step against a real node, so an agent can tell which conclusions are backed by Bitcoin Core and which depend on rules no node implements.

## The workflow

A typical session, as agents run it:

1. **Orient.** `describe` (overview and example), then `describe` on the forms the task needs (`define-tx`, `contract`, `spend`, …).
2. **Set up.** `(reset-session!)` if needed, define chains and keys, mine coins to the people who need them, then mature them with `(void (mine 100 #:on chain))` (no `#:to` pays an anonymous miner and keeps the keys' coins clean). Mine all needed coins early: the subsidy halves every 150 blocks.
3. **Build and test.** Build transactions with `define-tx` or `spend`; use `try` to test without changing state, `confirm` to commit. Read rejections and `explain` them.
4. **Branch.** `snapshot` before exploring alternatives; `restore` to go back.
5. **Analyse.** `branches` for spend paths, `commits`/`free-fields`/`mutate` for signatures, `sighash-search` for flag choices, `audit` and `diff-consensus` for rule sets.
6. **Verify.** `replay` the scenario log against real nodes and report anything not `confirmed`.

## Measured agent runs

Each scenario was handed to a fresh agent with only the goal in prose, no DSL code, and no access to the repository: only the MCP tools. What it hit was fixed and the run repeated.

| Run | Task | Tool calls | Result |
|---|---|---|---|
| 1 | Scenarios 1–3 and replay | 51 (27 describe) | all done; replay 21 confirmed, 0 disagree |
| 2 | Scenarios 1–3 and replay, after fixes | 32 (16 describe) | all done, one error; replay 18 confirmed |
| 3 | Scenario 4, both replays | 34 (14 describe) | all done; 14 confirmed on Core + Inquisition |

Typical fixes from these runs: long outputs abbreviated, the halving and maturity documented, a worked example in `describe`, rule names consistent between results and `explain`, eval errors that say which form failed, and accessors for replay results.

## Writing prompts

- State the goal and the facts (amounts, keys, timelocks), not the code.
- Ask for evidence: "show which rule rejected it", "explain the failing step", "replay it and report anything not confirmed".
- For comparisons, ask for snapshots ("try the refund, then restore and try the claim").
- For soft-fork questions, ask for `diff-consensus` and `audit` on each chain, and replay with an Inquisition target.

## Building other integrations

The server is a plain JSON-RPC 2.0 stdio process (`racket -l bitcoin/mcp`, one message per line) implementing `initialize`, `tools/list`, `tools/call` and `ping`. `tests/mcp.rkt` drives it both in-process and over real stdio, and is a good template. In Racket, `make-session` and `handle-message` from `bitcoin/mcp` give the same behaviour without stdio.
