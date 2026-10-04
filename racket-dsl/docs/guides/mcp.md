# Using it over MCP

The DSL runs as an [MCP](https://modelcontextprotocol.io) server holding one live session. You talk to an agent (for example Claude Code); the agent writes DSL code, sends it to the server, reads the results and reports back. You do not need to write Racket yourself.

## Set up

1. [Install the package](../getting-started.md#install-the-package) and make sure `racket -l bitcoin/mcp` starts (it waits silently on stdin; stop it with Ctrl-D).
2. The repository's `.mcp.json` already registers the server for Claude Code:

    ```json
    {"mcpServers": {"bitcoin-dsl": {"type": "stdio", "command": "racket", "args": ["-l", "bitcoin/mcp"]}}}
    ```

    To register it yourself instead (for example at user scope):

    ```sh
    claude mcp add --scope user bitcoin-dsl -- racket -l bitcoin/mcp
    ```

3. Start Claude Code in the repository. Project servers need approval the first time; approve `bitcoin-dsl`. `/mcp` shows whether it is connected.

Any MCP client that speaks stdio works the same way: run `racket -l bitcoin/mcp` as the server command.

## Asking for things

Describe the goal, not the code. The agent discovers the language through `describe`. Prompts that work well:

- "Fund Alice on a chain, pay Bob 49.99 BTC with 0.009 change, confirm it and show me the fee."
- "Write an HTLC where Bob claims with a preimage and Alice refunds after 144 blocks. Show both spend paths, try the refund too early and explain why it fails, then show both paths succeeding using a snapshot."
- "Which sighash flags let Carol add a fee input to Alice's payment without invalidating her signature, while keeping Alice's outputs fixed? Compare segwit v0 and taproot."
- "Define bitcoin plus CTV, run a vault on a chain with and without it, and audit it on both."
- "Replay this session against regtest Core and tell me if anything disagrees."

Results come back as data, so you can ask follow-up questions about any of them: "which rule rejected it?", "explain trace 3", "what does that signature commit to?".

## The tools

| Tool | What it does |
|---|---|
| `describe` | Self-description: purpose, conventions, tips, an example and every form with its usage. With a topic: a form, rule, opcode, group or consensus name, or `rules`, `opcodes`, `sighash`, `state`, `example`. |
| `eval` | Evaluates DSL forms in the session. Definitions and chain state persist across calls. Forms run in order; an error stops the batch and says which form failed. Long lists are abbreviated. |
| `snapshot` | Captures chain state and the scenario log; returns an id. Racket definitions are not captured. |
| `restore` | Returns chains and the log to a snapshot. |
| `explain` | Shows a validation trace: every rule and opcode in order, stacks top first, and the failing rule's doc. Takes a trace id, or the last trace. |

The session is the language `#lang bitcoin/conform`, so replay is available inside it.

## Watching what the agent does

Every tool call shows the code sent and the result. Things worth knowing when reading them:

- `try` never changes state; `broadcast` adds to the mempool; `confirm` broadcasts and mines a block.
- A rejection names a consensus rule (`#:rule`) and its details (`#:need 144 #:have 1`). `explain` on its `#:trace` id shows how it was reached.
- `(describe 'state)` shows every chain's height, mempool size and UTXO count.
- `reset-session!` drops all chains, traces and the log, but Racket definitions remain.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Server not listed or pending | Restart Claude Code in the repository and approve it; check with `/mcp`. |
| Changes to the DSL not visible | Run `raco setup --pkgs bitcoin-dsl`, then reconnect the server from `/mcp`. |
| `replay` steps all `unverified` with `target-binary-missing` | Put `bitcoind` on `PATH`, or build [Inquisition](../getting-started.md#bitcoin-inquisition-optional) for CTV chains. |
| An `eval` times out | Calls are limited to 300 seconds; split long work (big replays) into smaller calls. |

To try the server by hand, pipe JSON-RPC lines into it:

```sh
printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"eval","arguments":{"code":"(btc 1.5)"}}}' \
 | racket -l bitcoin/mcp
```
