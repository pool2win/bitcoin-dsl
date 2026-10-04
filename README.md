# Bitcoin DSL

The Bitcoin DSL is a language for Bitcoin systems and new Bitcoin ideas. With it, you describe chains, transactions, scripts, covenants and soft-fork proposals. Then you check each result against real Bitcoin nodes.

**Documentation:** <https://pool2win.github.io/bitcoin-dsl/>

## Use it through an agent

The primary method is to talk to an AI agent, for example Claude Code. The agent uses the DSL through its MCP server. You give the goal in your words, and the agent writes and runs the DSL code.

1. Install Racket 9 or later.
2. Link the package from the root of the repository:

    ```sh
    raco pkg install --link --name bitcoin-dsl .
    ```

3. Start Claude Code in the repository. The file `.mcp.json` registers the server.
4. Approve the `bitcoin-dsl` server.
5. Tell the agent what you want to model.

## Write the code yourself

The DSL is also a Racket language. If you prefer to write the code manually, write a Racket module:

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

(confirm pay)   ; => (accepted #:chain mainnet #:tx #<tx pay …> #:step 4 #:trace 1)
(fee pay)       ; => (btc 0.001)
```

## Tests

```sh
raco setup --pkgs bitcoin-dsl
raco test tests
```

The replay tests need `bitcoind` on `PATH`. Without it, they stop without failure.

## The files

| Path | Contents |
|---|---|
| `model.rkt`, `conform.rkt`, `mcp.rkt`, `private/` | The language, the replay and the MCP server. |
| `tests/` | The tests. |
| `docs/` | The documentation site. `docs/design/` holds the design notes. |
| `obsolete-ruby-dsl/` | The old Ruby DSL. We keep it for reference only. |

## License

See `COPYING`.
