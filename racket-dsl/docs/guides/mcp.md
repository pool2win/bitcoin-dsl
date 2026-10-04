# Use the MCP server

The DSL operates as an [MCP](https://modelcontextprotocol.io) server that holds one live session. You talk to an agent, for example Claude Code. The agent writes DSL code, sends it to the server, reads the results and gives you a report. You do not have to write Racket.

## Install the server

1. [Install the package](../getting-started.md#install-the-package).
2. Make sure that `racket -l bitcoin/mcp` starts. The server waits on stdin and shows nothing. To stop it, push Ctrl-D.
3. Start Claude Code in the repository. The file `.mcp.json` registers the server:

    ```json
    {"mcpServers": {"bitcoin-dsl": {"type": "stdio", "command": "racket", "args": ["-l", "bitcoin/mcp"]}}}
    ```

4. Approve the `bitcoin-dsl` server. Claude Code asks for approval of a project server the first time.
5. Type `/mcp` to make sure that the server is connected.

To register the server for all your projects, use this command:

```sh
claude mcp add --scope user bitcoin-dsl -- racket -l bitcoin/mcp
```

Other MCP clients that use stdio operate in the same way. Use `racket -l bitcoin/mcp` as the server command.

## Ask for results

Tell the agent the goal, not the code. The agent learns the language through `describe`. These prompts give good results:

- "Fund Alice on a chain, pay Bob 49.99 BTC with 0.009 change, confirm it and show me the fee."
- "Write an HTLC where Bob claims with a preimage and Alice gets a refund after 144 blocks. Show both spend paths. Try the refund too early and explain the failure. Then use a snapshot to show that both paths succeed."
- "Which sighash flags let Carol add a fee input to the payment of Alice without a change to the signature of Alice? Keep the outputs of Alice fixed. Compare segwit v0 and taproot."
- "Define bitcoin plus CTV. Run a vault on a chain with CTV and on a chain without it. Audit the vault on both chains."
- "Replay this session against regtest Core. Tell me if a step disagrees."

The results are data. You can ask questions about each result, for example "Which rule rejected it?", "Explain trace 3" or "What does that signature commit to?".

## The tools

| Tool | Function |
|---|---|
| `describe` | Gives the purpose, conventions, tips, an example and each form with its usage. A topic can be a form, rule, opcode, group or consensus name, or `rules`, `opcodes`, `sighash`, `state` or `example`. |
| `eval` | Evaluates DSL forms in the session. Definitions and the state of the chains stay between calls. The forms run in order. An error stops the batch, and the reply gives the form that failed. Long lists are shown in a short form. |
| `snapshot` | Captures the state of the chains and the scenario log, and returns an id. It does not capture Racket definitions. |
| `restore` | Puts the chains and the log back to a snapshot. |
| `explain` | Shows a validation trace: each rule and each opcode in order, the stacks with the top item first, and the doc of the rule that failed. It takes a trace id. Without an id, it uses the last trace. |

The session uses the language `#lang bitcoin/conform`. Thus `replay` is available in the session.

## Read the work of the agent

Each tool call shows the code that the agent sent and the result. Use these facts to read them:

- `try` does not change the state. `broadcast` adds the tx to the mempool. `confirm` broadcasts the tx and mines a block.
- A rejection gives the name of a consensus rule (`#:rule`) and its details, for example `#:need 144 #:have 1`. Use `explain` with the `#:trace` id to see the steps to the rejection.
- `(describe 'state)` shows the height, the mempool size and the number of UTXOs of each chain.
- `reset-session!` removes all chains, traces and the log. The Racket definitions stay.

## Problems and solutions

| Problem | Solution |
|---|---|
| The server is not in the list, or it waits for approval | Start Claude Code again in the repository and approve the server. Use `/mcp` to see the status. |
| Changes to the DSL do not show | Run `raco setup --pkgs bitcoin-dsl`. Then connect the server again from `/mcp`. |
| All `replay` steps are `unverified` with `target-binary-missing` | Put `bitcoind` on `PATH`. For CTV chains, build [Inquisition](../getting-started.md#bitcoin-inquisition-optional). |
| An `eval` call stops after 300 seconds | Divide long work, for example large replays, into smaller calls. |

To test the server manually, send JSON-RPC lines to it:

```sh
printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"eval","arguments":{"code":"(btc 1.5)"}}}' \
 | racket -l bitcoin/mcp
```
