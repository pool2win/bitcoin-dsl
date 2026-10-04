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

## Where the code is

`racket-dsl/` (branch `racket-dsl`), a Racket package providing collection `bitcoin`. Link it once with `raco pkg install --link --name bitcoin-dsl racket-dsl`, then run tests with `raco test racket-dsl/tests`.

- Step 1 (done): core values, consensus as a value with named rules and trace hooks. Scenario 1 runs (`tests/scenario-1.rkt`).
- Step 2 (done): policy language compiled to P2WSH, `branches`, `#:path`, `#:reveal`, CSV/CLTV/BIP68/nLockTime rules, `explain`, `snapshot`/`restore`. Scenario 2 runs (`tests/scenario-2.rkt`).

- Step 3 (done): all six BIP143 sighash flag combinations, `sig-of`, `commits`, `free-fields`, `mutate`, `edit`, `add-input`. Taproot `(tr key #:leaves ...)` with key and script path spends, a BIP341 selector (SIGHASH_DEFAULT, SINGLE without an output is invalid) and BIP342's strict CHECKSIG for non-empty bad signatures. Scenario 3 runs up to `sighash-search`, which is v1 (`tests/scenario-3.rkt`). `tests/sighash.rkt` and `tests/taproot.rkt` check that `free-fields` agrees with verification for every flag combination on `wpkh`, `tr-key` and `tr-script`.

- Step 4 (done): typed scenario log, `lower` and `replay` against a throwaway regtest Core node (`#lang bitcoin/conform`). Real crypto is pure Racket (`private/real/`: secp256k1 ECDSA with RFC6979, RIPEMD160, HMAC). Scenarios 1, 2 and 3 replay with zero disagreements (`tests/replay-*.rkt`), as does the BIP143 flag-by-edit matrix (`tests/replay-sighash.rkt`). `tests/replay-checks.rkt` shows a deliberately wrong model producing a `disagree`, and taproot and target-less chains producing `unverified`. Replay tests skip when `bitcoind` is not on PATH.

- Step 5 (server built; first agent run done): an agent given only prose goals completed Scenarios 1-3 and a replay (21 confirmed, 0 disagree) in 51 tool calls, using only the MCP tools. Its friction led to: abbreviated long lists in eval replies, `height`, subsidy/halving/maturity and `older` counting in describe, a worked `example` topic and tips, docs for script-level rules (`eval-false` etc.) with explain naming them via `#:as`, an anonymous-miner key no user key can collide with, and `add-input` naming its tx `<name>+input`. A second agent run took 32 tool calls (16 describe) with one error and a clean replay (18 confirmed). Its friction led to: eval reporting which form of a batch failed, form usages in the describe overview, a `sighash` describe topic, `#:fields` on commitment-mismatch rejections, and doc fixes for spend, define-tx and edit. Step 5 is done.
- Step 5 details: `racket -l bitcoin/mcp` is an MCP server over stdio holding one persistent `bitcoin/conform` session, with tools `describe`, `eval`, `snapshot`, `restore`, `explain`. `(describe)` is also a DSL function backed by a docs registry (`private/describe.rkt`). `tests/mcp.rkt` runs the Scenario 1-3 files through `eval`, plus snapshot/restore, explain, errors, replay and a stdio round trip. Register with `claude mcp add bitcoin-dsl -- racket -l bitcoin/mcp` to let an agent drive it.

- Taproot lowering (done): BIP340 Schnorr (zero aux, deterministic), TapTweak, real tapleaf/tapbranch hashes, control blocks, and the BIP341 digest rebuilt from committed fields. `tests/replay-taproot.rkt` replays all of `tests/taproot.rkt` against Core with zero disagreements: key and script paths, every flag by edit, strict tapscript CHECKSIG, a forged control block, SINGLE without an output.

- v1 (done): opcodes identified by byte (`private/script.rkt` registry; consensus tables keyed by byte; NOP1, NOP4-NOP10 upgradable); `define-consensus`/`diff-consensus`/`audit` (`private/compose.rkt`); CTV as a proposal opcode with `template` and a `(ctv t)` policy fragment (`private/proposals.rkt`), real BIP119 hash checked against Inquisition's vectors (`tests/ctv-vectors.rkt`); replay gated on the target/chain consensus diff, block-validity verdicts when a mempool refuses a tx, an Inquisition target; `sighash-search` (`private/inspect.rkt`) and `sighash-matrix` (`private/conform.rkt`). Scenario 4 runs and replays with zero disagreements (`tests/scenario-4.rkt`, `tests/replay-4.rkt`); Scenario 3 runs in full; the matrix covers 260 cells (`tests/replay-matrix.rkt`). Bitcoin Inquisition is built at `~/projects/bitcoin-inquisition` (CTV is always active on its regtest).

Choices made along the way:
- `snapshot`/`restore` rewind chains and the scenario log; traces are kept so trace ids stay valid. After a restore the log is the history of the current branch.
- A branch's witness template gets an empty item for any signature or preimage not supplied, so an incomplete spend is an explained rejection rather than a build error.
- `thresh` supports only `pk` subs so far; time-based relative and absolute locks are marked unsupported.
- A commitment is an alist from field name to value; names are relative to the signing input. `mutate`/`free-fields` re-run the selector on the edited tx rather than reasoning about flags.
- `(inputs remove-others)` is free only if every signed input survives alone and the input set is not committed, so a one-input SIGHASH_ALL tx does not pass vacuously.
- Selectors take the spend context: `(tx index spent-coins type leaf)`, leaf being the tapleaf hash for a script path. Branch witness templates are complete (wsh script, tapleaf script and control block included).
- Lowering derives keys and preimages from names (`sha256("bitcoin-dsl/key/<name>")`), so real txids are deterministic; model txids map to real ones during replay. A lowered signature signs the BIP143 digest rebuilt from its committed fields, not the current tx.
- Replay nodes run with `-acceptnonstdtxn=1 -minrelaytxfee=0 -blockmintxfee=0 -dustrelayfee=0` and RPC `maxfeerate=0`: the harness checks consensus, not policy. A mined block is checked for height, coinbase reward and the set of included txs.
- MCP `snapshot`/`restore` rewind chains and the log, not Racket definitions. `eval` captures stdout/stderr into the result, stops at the first error (keeping earlier output), and has a 300s limit. Lists of lists print one element per line so keyword pairs stay together.
- After changing modules, run `raco setup --pkgs bitcoin-dsl`: the MCP server loads `bitcoin/conform` dynamically, so `raco make` on one file does not rebuild it.
- Lowered tapscript uses 32-byte x-only keys; scriptPubKeys always lower with compressed keys. Real tapbranches sort children by bytes while the model sorts by printed form; the tree shape is identical, so control blocks agree.
- A proposal opcode registers itself (`register-opcode!`) and is named in `define-consensus` without being evaluated. `(replace n r)` requires `r` to have the name `n`. The world box is a parameter (`current-world-box`) so `sighash-matrix` runs in a scratch session.
- Replay gates on opcodes and rules, not parameters, so a model whose parameters are wrong still shows up as a `disagree`. Txids in replay are keyed by chain, since two chains produce identical model txids.
- A taproot key-path signature is by the internal key; the tweak is implied by the symbolic output key `(taptweak (internal root))`. Taptree is balanced over the leaves in order; tapbranch orders children by printed form. Leaf scripts compile exactly as for wsh (no CHECKSIGADD yet); OP_SUCCESSx, annex and sigops budget are not modelled.

## Documentation

User and agent docs live in `racket-dsl/docs/` (MkDocs Material; `racket-dsl/mkdocs.yml`). Reference pages are generated from the describe registry (`racket docs/gen-reference.rkt`, checked by `tests/docs.rkt`); scenario pages include the test files. `CLAUDE.md` requires keeping them current. Publishing (GitHub Actions, custom domain) is not set up yet.

## Next step

v2, Scenario 5: share chains (`#:kind share-chain`, `#:parent`), `miners` with seeded hashrate, `network` latency, simulated time, `run`, `repeat` with statistics. Fill in real p2poolv2 parameters first. An agent given Scenario 4's goals in prose completed it over MCP in 34 tool calls, including both replays; its friction led to binding `inquisition` in eval, `regtest`/`run-steps`/`unverified-steps` docs and group topics in describe, `#:expected`/`#:got` on CTV mismatches, and `spend #:name`.

## Things to fill in

- Real p2poolv2 parameters for Scenario 5 (share spacing, ASERT half-life, PPLNS window) are placeholders.
- Open questions are listed at the end of `scenarios.md`.
