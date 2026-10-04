# Codebase and tests

## The files

```
racket-dsl/
  model.rkt            #lang bitcoin/model: Racket plus the forms and macros for models
  conform.rkt          #lang bitcoin/conform: the model plus replay
  mcp.rkt              the MCP server (racket -l bitcoin/mcp)
  private/
    amount.rkt         exact amounts in satoshis
    crypto.rkt         symbolic keys, secrets, hashes, signatures; sighash flags
    policy.rkt         the policy language, compilation to Script, branches
    values.rkt         locks (wpkh, wsh, tr), coins, transactions, taproot trees
    script.rkt         the Script interpreter and the registry of opcode bytes
    consensus.rkt      rules, opcodes, sighash selectors, validation; the bitcoin value
    compose.rkt        extend-consensus, diff-consensus, audit, registries
    proposals.rkt      proposal opcodes: CTV and templates
    session.rkt        chains, mining, mempool, traces, snapshots, explain
    log.rkt            events of the scenario log
    inspect.rkt        sig-of, commits, edit, mutate, free-fields, sighash-search, audit
    describe.rkt       the registry for self-description
    result.rkt         accepted, rejected, unverified
    conform.rkt        replay, targets, sighash-matrix
    real/              lowering: hashes, secp256k1 (ECDSA, Schnorr), BIP143, BIP341, BIP119, the regtest node
  tests/               one file for each scenario, each area of rules and each replay
  docs/                this site (MkDocs Material)
```

## Tests

1. After you change modules, rebuild them:

    ```sh
    raco setup --pkgs bitcoin-dsl
    ```

2. Run the tests:

    ```sh
    raco test racket-dsl/tests
    ```

| Tests | Subjects |
|---|---|
| `scenario-N.rkt` | Each scenario in the model. |
| `replay-N.rkt`, `replay-taproot.rkt`, `replay-sighash.rkt`, `replay-matrix.rkt`, `replay-checks.rkt` | The same scenarios against real nodes. These tests stop without failure if `bitcoind` is not available. |
| `rules.rkt`, `policy.rkt`, `sighash.rkt`, `taproot.rkt`, `compose.rkt`, `ctv.rkt` | The areas of rules. |
| `crypto.rkt`, `ctv-vectors.rkt` | Test vectors with known answers (RFC6979, BIP340, BIP119). |
| `mcp.rkt` | The server: scenarios through `eval`, the tools, errors and the stdio format. |
| `docs.rkt` | The generated reference pages are current, and the pages follow the ASD-STE100 rules that a machine can check. |

## Add a feature

**A form**

1. Write the form and export it from `model.rkt` or `conform.rkt`.
2. Add an entry to `private/describe.rkt`, thus agents can find the form.
3. Run `racket docs/gen-reference.rkt`.

**A consensus rule**

- Add a `rule` to `bitcoin-rules` in `private/consensus.rkt`, with a name, a scope, a doc and a check.
- For a proposal, add the rule in a `define-consensus`.

**A proposal opcode.** Use CTV in `private/proposals.rkt` as the example:

1. Make an opcode value at the byte of an upgradable NOP, with docs for its failures.
2. Register it with `register-opcode!`.
3. If contracts must use it, add a policy fragment.
4. If it adds a new hashed value, tell `private/real/lower.rkt` how to lower that value.
5. For replay, add a target that runs the opcode.

**A scenario**

1. Write `tests/scenario-N.rkt`.
2. Write `tests/replay-N.rkt`.
3. Write a page in `docs/scenarios/`.
4. Give the goal in prose to an agent, and let the agent run the scenario over MCP.

The history of the design and the decisions are in `docs/design/` at the root of the repository.
