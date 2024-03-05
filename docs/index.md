---
layout: page
nav_order: 1
---

# Mission

Make it easy to build and execute bitcoin transactions.

---

## What Bitcoin DSL is NOT?

### Not a language to specify Script

Bitcoin DSL is not just a way to write Bitcoin Scripts for transaction
outputs. [Miniscript](https://bitcoinops.org/en/topics/miniscript/)
and
[Descriptors](https://github.com/bitcoin/bitcoin/blob/master/doc/descriptors.md)
already do a great job of this.

### Not dependent on a specific BIP

Bitcoin DSL is not meant to demonstrate any new bitcoin improvements
opcodes or forks.


## What is Bitcoin DSL?

Bitcoin DSL makes it easier to experiment with Bitcoin transactions
and contracts by providing a highlevel language to build and execute
transactions.

### Declarative Syntax

The DSL specifies what needs to be done, not how.

For example, we simply declare what a transaction should look like and
don't have to construct it one command at a time. The DSL uses sane
defaults like using SegWit and defaulting to P2SWH, etc.

```ruby
@alice_to_bob = transaction inputs: [
                              { tx: @alice_coinbase, vout: 0, script_sig: 'p2wpkh:alice' }
                            ],
                            outputs: [
                              { address: 'p2wpkh:bob', amount: 49.99.sats }
                            ]
```

Jump to [Declarative Syntax]({% link _overview/declarative_syntax.md %})

---

### High level language for locking and unlocking Script

The DSL supports raw Script and Miniscript to specify outputs.

#### Locking Script

```ruby
# Specify output using miniscript Policy
...
outputs: [
  {
    policy: 'or(99@thresh(2,pk($alice),pk($asp)),and(older(10),pk($asp_timelock)))',
    amount: 49.999.sats
  }
]
...
# Specify output using Script
outputs: [
  {
    policy: 'OP_DUP OP_HASH160 hash160:$alice OP_EQUALVERIFY OP_CHECKSIG',
    amount: 49.999.sats
  }
]
...
```

#### Unlocking Script

```ruby
...
# Specify script sig using high level constructs
inputs: [ { tx: @alice_bob_tx, vout: 0, script_sig: 'multisig:alice,asp' } ]
...

# Specify script sig using Script
inputs: [ { tx: @alice_bob_tx, vout: 0, script_sig: 'sig:$alice $alice' } ]
```

Jump to [Bitcoin Scripting]({% link _overview/scripting.md %})

---

### Contract Branch Executions

DSL makes it easy way to run various branches of a contract
specification, by allowing composition of scripts.

```ruby
# Load and run setup script
run './lib/ark/setup.rb'

# Next create and spend a transaction 
@spend_tx = transaction inputs: [...], outputs: [...]
```

Jump to [Contract Branch Executions]({% link _overview/branch_executions.md%})

---

### Interact with bitcoin node

All the JSON-RPC API commands are directly available from the DSL, so
we don't have to copy paste transactions around, and can query the
bitcoin node to find transactions and then operate on them.

```ruby
broadcast @alice_boarding_tx
extend_chain to: @alice

assert_confirmed transaction: @alice_boarding_tx
```

Jump to [Node Interaction]({% link _overview/node_interaction.md %})

---
