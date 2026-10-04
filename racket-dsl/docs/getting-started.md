# Getting started

## Requirements

- **Racket 9** or later. On Arch/Manjaro: `sudo pacman -S racket`; elsewhere see [racket-lang.org](https://racket-lang.org).
- **Bitcoin Core** (`bitcoind` on `PATH`) for conformance replay. Optional: the model works without it, and replay tests skip when it is missing.
- **Bitcoin Inquisition** for replaying CTV steps. Optional; see [below](#bitcoin-inquisition-optional).

## Install the package

The language lives in `racket-dsl/`, a Racket package that provides the collection `bitcoin`. Link it once from the repository root:

```sh
raco pkg install --link --name bitcoin-dsl racket-dsl
```

This makes `#lang bitcoin/model`, `#lang bitcoin/conform` and `racket -l bitcoin/mcp` available. To remove it: `raco pkg remove bitcoin-dsl`.

After changing any module, rebuild everything (the MCP server loads modules at runtime, so `raco make` on one file is not enough):

```sh
raco setup --pkgs bitcoin-dsl
```

## Run the tests

```sh
raco test racket-dsl/tests
```

The suite covers every scenario, the rules, the crypto (with BIP340 and BIP119 test vectors), and replay against real nodes. Replay tests start throwaway regtest nodes in temporary directories and stop them afterwards; they never touch `~/.bitcoin`.

## Your first scenario

Save this as `first.rkt` and run `racket first.rkt`:

```racket
#lang bitcoin/model
(chain mainnet #:rules bitcoin)
(keys alice bob)

(define cb (first (mine 1 #:on mainnet #:to alice)))
(try (spend cb #:sign alice #:outputs (list (output 'b (wpkh bob) (btc 49)))))
; => (rejected #:chain mainnet #:rule coinbase-maturity #:input 0 #:need 100 #:have 1 #:step 3 #:trace 1)

(void (mine 99 #:on mainnet))
(try (spend cb #:sign alice #:outputs (list (output 'b (wpkh bob) (btc 49)))))
; => (accepted #:chain mainnet #:tx #<tx …> #:step 5 #:trace 2)
```

Then add `(explain (last-trace))` to see every rule and opcode that ran.

To check it against a real node, switch the first line to `#lang bitcoin/conform` and add:

```racket
(summary (replay (scenario-log) #:targets (hash 'mainnet (regtest))))
```

## Use it from Claude Code

The repository's `.mcp.json` registers the MCP server. Start Claude Code in the repository, approve the `bitcoin-dsl` server, and ask for what you want. See [Using it over MCP](guides/mcp.md).

## Bitcoin Inquisition (optional)

Replaying CTV steps needs a node that enforces CTV. Bitcoin Inquisition activates CTV (and other proposals) on regtest. Build only `bitcoind`:

```sh
git clone --depth 1 https://github.com/bitcoin-inquisition/bitcoin.git ~/projects/bitcoin-inquisition
cd ~/projects/bitcoin-inquisition
cmake -B build -G Ninja -DENABLE_WALLET=OFF -DBUILD_GUI=OFF -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF -DENABLE_IPC=OFF -DWITH_ZMQ=OFF
cmake --build build --target bitcoind -j"$(nproc)"
```

`(regtest #:build 'inquisition)` finds it at `~/projects/bitcoin-inquisition/build/bin/bitcoind`, or wherever the `BITCOIN_INQUISITION` environment variable points.
