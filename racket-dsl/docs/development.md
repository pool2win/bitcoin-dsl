# Codebase and tests

## Layout

```
racket-dsl/
  model.rkt            #lang bitcoin/model: Racket plus the modelling forms and macros
  conform.rkt          #lang bitcoin/conform: model plus replay
  mcp.rkt              the MCP server (racket -l bitcoin/mcp)
  private/
    amount.rkt         exact satoshi amounts
    crypto.rkt         symbolic keys, secrets, hashes, signatures; sighash flags
    policy.rkt         the policy language, compilation to Script, branches
    values.rkt         locks (wpkh, wsh, tr), coins, transactions, taproot trees
    script.rkt         the Script interpreter and the opcode byte registry
    consensus.rkt      rules, opcodes, sighash selectors, validation; the bitcoin value
    compose.rkt        extend-consensus, diff-consensus, audit, registries
    proposals.rkt      proposal opcodes: CTV and templates
    session.rkt        chains, mining, mempool, traces, snapshots, explain
    log.rkt            scenario log events
    inspect.rkt        sig-of, commits, edit, mutate, free-fields, sighash-search, audit
    describe.rkt       the self-description registry
    result.rkt         accepted / rejected / unverified
    conform.rkt        replay, targets, sighash-matrix
    real/              lowering: hashes, secp256k1 (ECDSA, Schnorr), BIP143/341/119, the regtest node
  tests/               one file per scenario, rule area and replay
  docs/                this site (MkDocs Material)
```

## Tests

```sh
raco setup --pkgs bitcoin-dsl   # after changing modules
raco test racket-dsl/tests
```

| Tests | Cover |
|---|---|
| `scenario-N.rkt` | each scenario in the model |
| `replay-N.rkt`, `replay-taproot.rkt`, `replay-sighash.rkt`, `replay-matrix.rkt`, `replay-checks.rkt` | the same against real nodes; skip without `bitcoind` |
| `rules.rkt`, `policy.rkt`, `sighash.rkt`, `taproot.rkt`, `compose.rkt`, `ctv.rkt` | rule areas |
| `crypto.rkt`, `ctv-vectors.rkt` | known-answer vectors (RFC6979, BIP340, BIP119) |
| `mcp.rkt` | the server: scenarios through `eval`, tools, errors, stdio framing |
| `docs.rkt` | the generated reference pages are current |

## Adding things

- **A form:** implement it, export it from `model.rkt` (or `conform.rkt`), add a `private/describe.rkt` entry so agents can find it, and run `racket docs/gen-reference.rkt`.
- **A consensus rule:** add a `rule` to `bitcoin-rules` in `private/consensus.rkt` (name, scope, doc, check), or add it in a `define-consensus` for a proposal.
- **A proposal opcode:** follow CTV in `private/proposals.rkt`: an opcode value at an upgradable NOP's byte with docs for its failures, registered with `register-opcode!`; a policy fragment if contracts should use it; lowering in `private/real/lower.rkt` for any new hashed value; and a target that runs it, for replay.
- **A scenario:** a `tests/scenario-N.rkt`, a `tests/replay-N.rkt`, a page under `docs/scenarios/`, and an agent run over MCP from a prose goal.

Design history and decisions are in `docs/design/` at the repository root.
