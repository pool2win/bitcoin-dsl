# How agents use the DSL

The design of the DSL is for agents first. An agent with no knowledge of the DSL can connect to the [MCP server](mcp.md) and learn the language from the server. Then it can model a scenario from start to end. This page gives the design decisions that make this possible and the procedure that agents use. Use it to write prompts or to make other agent integrations.

## The design for agents

**Self-description.** `describe` without a topic returns the purpose, conventions, tips, a full example and each form with its usage. Each form, rule, opcode, group or consensus name is also a topic. The MCP `instructions` of the server tell the agent to call `describe` first.

**Results are data.** The DSL does not print. Each query returns a value with a fixed shape. The agent can make decisions from the value:

```racket
(accepted #:chain mainnet #:tx #<tx pay 20a17961> #:step 4 #:trace 1)
(rejected #:chain mainnet #:rule sequence-lock #:input 0 #:need 144 #:have 1 #:step 9 #:trace 3)
```

**Each rejection gives the name of a rule.** The `#:rule` comes from the consensus value of the chain. `(describe 'sequence-lock)` documents the rule. `explain` with the `#:trace` id shows the rules and opcodes that ran before the failure. A script failure gives the specific failure, for example `eval-false` or `ctv-template-mismatch`. Its `#:cause` or `#:fields` gives the reason.

**The same input gives the same output.** The DSL derives keys from names, and the time is simulated. The results come in a fixed order: `utxos` sorts by confirmation height, then by outpoint. Thus the same code gives the same txids each time, in the model and on the real node.

**Alternatives are easy.** `snapshot` and `restore` put the chains and the scenario log back to an earlier state. An agent can try one spend path, return to the snapshot and try a different path.

**Coins are explicit.** Coins come only from `mine` or from outputs with labels. The DSL does not select coins. Thus an agent always knows which coin a transaction spends.

**The results are checked against real nodes.** `replay` lowers the session to real bytes and checks each step against a real node. An agent can tell which conclusions Bitcoin Core supports, and which conclusions depend on rules that no node has.

## The procedure

Agents usually do these steps:

1. Call `describe` to get the overview and the example.
2. Call `describe` for each form that the task uses, for example `define-tx`, `contract` or `spend`.
3. If the session has old state, call `(reset-session!)`.
4. Define the chains and the keys.
5. Mine coins to the keys that need them. Mine all the coins early, because the subsidy halves every 150 blocks.
6. Mature the coins with `(void (mine 100 #:on chain))`. Without `#:to`, the coinbases go to an anonymous miner.
7. Build the transactions with `define-tx` or `spend`.
8. Test each transaction with `try`. Use `confirm` to make the change permanent.
9. Read each rejection, and use `explain` to see the cause.
10. Make a `snapshot` before you try alternatives. Use `restore` to return to it.
11. Analyse the results: `branches` for spend paths; `commits`, `free-fields` and `mutate` for signatures; `sighash-search` for flags; `audit` and `diff-consensus` for rule sets.
12. Replay the scenario log against real nodes. Report each step that is not `confirmed`.

## Measured agent runs

We gave each scenario to a new agent. The agent got only the goal in prose. It got no DSL code and no access to the repository, only the MCP tools. After each run, we fixed the problems that the agent found, and we did the run again.

| Run | Task | Tool calls | Result |
|---|---|---|---|
| 1 | Scenarios 1 to 3, and replay | 51 (27 describe) | All done. Replay: 21 confirmed, 0 disagree. |
| 2 | Scenarios 1 to 3, and replay, after the fixes | 32 (16 describe) | All done with one error. Replay: 18 confirmed. |
| 3 | Scenario 4, with both replays | 34 (14 describe) | All done. 14 confirmed on Core and Inquisition. |

Typical fixes from these runs:

- Long outputs are shorter.
- `describe` documents the halving and the coinbase maturity, and it has a full example.
- The rule names in the results and in `explain` are the same.
- An error from `eval` gives the form that failed.
- Accessors read the results of a replay.

## Write prompts

- Give the goal and the facts: amounts, keys and timelocks. Do not give the code.
- Ask for evidence: "Show which rule rejected it", "Explain the step that failed", "Replay it and report each step that is not confirmed".
- For comparisons, ask for snapshots: "Try the refund, then restore and try the claim".
- For soft-fork questions, ask for `diff-consensus` and `audit` on each chain. Replay with an Inquisition target.

## Make other integrations

The server is a JSON-RPC 2.0 process on stdio (`racket -l bitcoin/mcp`, one message on each line). It has the methods `initialize`, `tools/list`, `tools/call` and `ping`. `tests/mcp.rkt` operates the server in the same process and through real stdio. Use it as an example. In Racket, `make-session` and `handle-message` from `bitcoin/mcp` give the same functions without stdio.
