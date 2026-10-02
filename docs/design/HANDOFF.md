# Racket Bitcoin DSL — Design Handoff

Context for continuing this work in Claude Code. Read this first, then `scenarios.md` (same folder), which holds the seven example scenarios, the derived v0 definition, the build order and open questions.

## Background

- **pool2win/bitcoin-dsl** (Ruby): works, but clunky. The clunkiness is mostly strings: descriptors, policies and Script live inside Ruby strings (`'sig:wpkh(@bob)'`, `'or(99@thresh(...))'`), so the host can't see inside them, errors arrive late and without source location. It runs against regtest bitcoind in docker.
- **pool2win/bsl** (Racket): earlier attempt; stalled on hand-writing a complete Script interpreter.

## Goal

A Racket DSL that agents drive to (1) describe existing Bitcoin systems and (2) explore new ideas by iterating on models of chains, transactions and scripts. Scope includes new opcodes and soft forks, new L2 protocols, and multiple chains with different consensus rules, each with their own L2 nodes/operators (e.g. the p2poolv2 share chain alongside bitcoin).

## Decisions so far

1. **Agents drive it through a live MCP/REPL session.** Nodes and state persist across calls. Tool surface stays small: `eval`, `snapshot`, `restore`, `explain`, `describe`.
2. **Two layers joined by a shared scenario log.**
   - **Model engine** (custom consensus): where agents design and iterate. Needed because p2poolv2's consensus (share chain, ASERT, uncles, PPLNS, MuHash) is not a bitcoind fork, so there is no binary to point at.
   - **Conformance system**: lowers a model scenario to real keys, signatures, tx bytes and blocks, then replays it against regtest bitcoind (and Inquisition or custom builds) and local p2poolv2 nodes. Per-step status: `confirmed`, `disagree`, or `unverified` (rule exists only in the model). Never silently pass.
   - Earlier option considered and dropped: "real consensus only" (each chain = a bitcoind build). It can't model p2poolv2 and gives verdicts without explanations.
3. **Consensus is a composable value, not a fixed interpreter.** `define-consensus` with `#:extends`; every rule is named and has a trace hook from day one. This is the one structural decision v0 must get right, or multi-chain and share chains become a rewrite.
4. **Don't repeat the bsl trap.** Implement opcodes and rules only as scenarios need them. Mark unimplemented things (e.g. legacy FindAndDelete/codesep) as unsupported rather than half-implementing.
5. **Symbolic crypto in the model, exact sighash.**
   - A signature is a value `(sig key commitment)`; verification recomputes the commitment and compares.
   - Sighash is a per-spend-version *field selector*: (tx, input index, spend context) → named set of committed fields. Legacy, BIP143 and BIP341 differ and live in the consensus value (BIP341: all prevout amounts and scriptPubKeys unless ANYONECANPAY, spend type, annex, leaf hash, codesep position, SIGHASH_DEFAULT vs ALL; legacy: SIGHASH_SINGLE out-of-range signs the constant 1).
   - Enables agent queries: `commits`, `free-fields`, `mutate`, `sighash-search`. New sighash modes, CTV, TXHASH and CSFS all fit as field selectors.
   - Conformance property test: mutating a field the model calls *free* must still be accepted by a real node; mutating a *committed* field must be rejected. Run as a matrix over spend types and flags.
6. **Agent-facing requirements:** structured results as data (`accepted` / `rejected #:rule ... #:trace ...` / `unverified`), determinism (seeded keys, mocked time, fixed result ordering), cheap snapshot/fork of state, branch enumeration as a first-class query, self-description via `describe`, actors with simulated time across chains.
7. **Coins are never picked implicitly.**
   - Every coin comes from `mine` (always returns a list of the coinbase coins it mined) or a labeled tx output.
   - `define-tx` is a *definition form* (macro): output labels are bare identifiers bound as variables, expanding to `(define to-bob (output-of pay 0))` etc.
   - `spend` is an *expression*: outputs are built with `(output 'label lock amount)` constructors, labels stored as data, looked up with `(out tx 'label)`.
   - `utxos` is an explicit query (`#:spendable-by`, `#:locked-by`) with a fixed order (confirmation height, then outpoint).

## Racket pitfalls already caught

- A macro can't introduce definitions from inside `(define pay (spend ...))`: the RHS is expression context. Hence `define-tx` as its own definition form.
- Naming a chain `btc` shadows the `(btc 49.99)` amount constructor. Chains are named `mainnet`, `signet`, etc.
- Quoting a whole output list (`'([to-bob (wpkh bob) (btc 49.99)])`) also quotes `(wpkh bob)` and `(btc 49.99)`, so they are never evaluated. Use the `output` constructor; avoid quasiquote in agent-facing APIs.

## Next step

Build order step 1 from `scenarios.md`: core values plus the rule-set representation (named rules with trace hooks). Done when Scenario 1 runs end to end in the model.

## Things to fill in

- Real p2poolv2 parameters for Scenario 5 (share spacing, ASERT half-life, PPLNS window) are placeholders.
- Open questions are listed at the end of `scenarios.md`.
