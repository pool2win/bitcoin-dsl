# Get started

## What you need

- **Racket 9** or later. On Arch or Manjaro, use `sudo pacman -S racket`. For other systems, see [racket-lang.org](https://racket-lang.org).
- **Bitcoin Core** (`bitcoind` on `PATH`) for conformance replay. This is optional. The model operates without it, and the replay tests stop without failure when it is not available.
- **Bitcoin Inquisition** to replay CTV steps. This is optional. See [Bitcoin Inquisition](#bitcoin-inquisition-optional).

## Install the package

The language is in `racket-dsl/`. It is a Racket package that gives the collection `bitcoin`.

1. Go to the root of the repository.
2. Link the package:

    ```sh
    raco pkg install --link --name bitcoin-dsl racket-dsl
    ```

After this step, `#lang bitcoin/model`, `#lang bitcoin/conform` and `racket -l bitcoin/mcp` are available. To remove the package, use `raco pkg remove bitcoin-dsl`.

After you change a module, rebuild all modules:

```sh
raco setup --pkgs bitcoin-dsl
```

!!! note
    `raco make` on one file is not enough. The MCP server loads the modules at run time.

## Run the tests

```sh
raco test racket-dsl/tests
```

The tests include each scenario, the rules, the crypto (with BIP340 and BIP119 test vectors) and replay against real nodes. The replay tests start temporary regtest nodes in temporary directories and stop them after the test. They do not touch `~/.bitcoin`.

## Your first scenario

1. Save this text as `first.rkt`:

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

2. Run `racket first.rkt`.
3. To see each rule and opcode that ran, add `(explain (last-trace))` and run the file again.

To check the scenario against a real node, do these steps:

1. Change the first line to `#lang bitcoin/conform`.
2. Add this line at the end of the file:

    ```racket
    (summary (replay (scenario-log) #:targets (hash 'mainnet (regtest))))
    ```

3. Run the file again.

## Use the DSL from Claude Code

The file `.mcp.json` in the repository registers the MCP server.

1. Start Claude Code in the repository.
2. Approve the `bitcoin-dsl` server.
3. Tell the agent what you want to model.

For more data, see [Use the MCP server](guides/mcp.md).

## Bitcoin Inquisition (optional)

To replay CTV steps, you must have a node that enforces CTV. Bitcoin Inquisition activates CTV and other proposals on regtest.

1. Get the source:

    ```sh
    git clone --depth 1 https://github.com/bitcoin-inquisition/bitcoin.git ~/projects/bitcoin-inquisition
    ```

2. Configure the build:

    ```sh
    cd ~/projects/bitcoin-inquisition
    cmake -B build -G Ninja -DENABLE_WALLET=OFF -DBUILD_GUI=OFF -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF -DENABLE_IPC=OFF -DWITH_ZMQ=OFF
    ```

3. Build only `bitcoind`:

    ```sh
    cmake --build build --target bitcoind -j"$(nproc)"
    ```

`(regtest #:build 'inquisition)` finds the binary at `~/projects/bitcoin-inquisition/build/bin/bitcoind`. To use a different location, set the `BITCOIN_INQUISITION` environment variable.
