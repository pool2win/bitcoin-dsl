
![CI Badge](https://github.com/pool2win/bitcoin-dsl/actions/workflows/contracts-ci.yml/badge.svg)

## Bitcoin DSL - Mission

Make is easy to experiment with bitcoin contracts.

## Goals

The three goals of the DSL are:

**Declarative syntax** - The DSL should specify what needs to be done,
not how. For example, to build a transaction, we should just say the
scriptsig is a `p2wpkh:bob` instead of making a series of imperative
calls to achieve the same goal.

**Easily execute branches in a contract execution** - Users should be
easily able to run the various branches that a contract can be
executed on.

**High level language for locking and unlocking Script** - Miniscript
is a nice tool for writing locking conditions in a higher level
language, however, we also want to enable writing scriptsigs in a
higher level language too.

**Interact with bitcoin node** - All the JSON-RPC API commands should
be directly available from the DSL, so we don't have to copy paste
transactions around, and can query the bitcoin node to find
transactions and then operate on them.

## Tools: Bitcoin Ruby and Rust-Miniscript

I was earlier trying to build an intricate DSL in Lisp, but for the
sake of quick iteration decided to build an internal DSL in
Ruby. Thankfully, we already have an extensive, well tested and
supported library to build bitcoin transactions in Ruby -
[bitcoinrb](https://github.com/chaintope/bitcoinrb) - a fantastic
bitcoin ruby library which provides all the building blocks I
needed. So my task was made much simpler - build an internal DSL
around bitcoinrb.

I want to leverage miniscript to specify scriptsig. For the same,
[rust-miniscript](https://github.com/rust-bitcoin/rust-miniscript)
provides a way to compile miniscript policy into Bitcoin Script. I
implemented a CLI wrapper around it and call it from within the Ruby
DSL to get the `script_pub_key` and the witness program from a
miniscript policy. The DSL later uses the witness program to sign the
transactions, all without requiring the user to track these
separately.

## Features

Currently the DSL allows easily doing the following:

1. Automatically start/stop a bitcoin node
1. Extend chain to generate coinbases or confirm transactions
1. Build transactions using a high level DSL
   1. `script_pub_key` can be specified using miniscript
   1. `script_sig` can be specified using high level constructs
1. Assert that a transaction has been accepted by mempool
1. Submit bitcoin transactions to a node
1. Query a bitcoin node to assert a transaction is confirmed

Here's how each of the above is done using the DSL.

## Starting a node

This is automagically handled by the DSL. When you run a DSL script, a
bitcoin node is setup and when the script finishes, the node is
cleaned up.

There's no commands required to start/stop a node. The DSL just does
it for you.

Here is a simple script to create a coinbase and make it spendable.

```ruby
@alice = key :new

# Mine 100 blocks, all with coinbase to alice.
extend_chain to: @alice, num_blocks: 101
```

This is how you run the above script

```bash
$ ruby lib/run.rb -s lib/simple.rb
Running script from lib/simple.rb
mkdir -p /tmp/x &&              bitcoind -datadir=/tmp/x -chain=regtest              -rpcuser=test -rpcpassword=test -daemonwait -txindex -debug=1
Bitcoin Core starting
I, [2024-03-01T21:01:13.580365 #73094]  INFO -- : Extending chain by 101 blocks to address bcrt1qy5a0ghjsnmlt4qt0akf7627wkwexljaz6tfame
kill -9 `cat /tmp/x/regtest/bitcoind.pid` && rm -rf /tmp/x
```

As you see above, the DSL automatically starts a new bitcoin node,
runs the script and at the end cleans up by stopping bitcoind and
deleting any data directories.


## Extend chain

We need to extend chain in a number of situations. When we need to
mine some coins to use them later or to confirm a transaction that has
been broadcast.

Let's look at both the cases.

### Extend chain to mine some coins

The following generates a new key and mines a block with coinbase
rewards sent to alice.

```ruby
# Generate new key and call it alice
@alice = key :new

# Extend chain mining coinbases to alice
extend_chain to: @alice
```

### Extend chain to confirm transactions

The following will mine 100 blocks. This will make all previously
generated coinbases spendable.

```ruby
extend_chain num_blocks: 100
```

In the above, we will generate a throw away key that get the coinbase
reward. If you want to generate coinbases controlled by a given key,
you can specify the `to` keyword as below:

```ruby
extend_chain num_blocks: 100, to: @alice
```

## Build transactions

I often need to find a spendable coinbase controlled by a key, then
create a transaction that spends the coinbase, creating a new UTXO for
with custom spending conditions.

The following script finds a coinbase spendable by Alice and sends
some bitcoin to Bob.

```ruby
# Find a coinbase that Alice can spend
@alice_coinbase = spendable_coinbase_for @alice

@alice_to_bob = transaction inputs: [
                              { tx: @alice_coinbase, vout: 0, script_sig: 'p2wpkh:alice' }
                            ],
                            outputs: [
                              { address: 'p2wpkh:bob', amount: 49.99.sats }
                            ]

```

Note the syntax to generate `script_sig` and `script_pub_keys`. In the
above transaction we are saying:

1. Sign the transaction knowing it is a p2wpkh output owned by Alice.
1. Create a p2wpkh output for Bob.

We can even use miniscript policies to generate `script_pub_keys` and
I demonstrate that next.

### Use miniscript policy

If we want to generate a multisig transaction we can use miniscript to
specify the spending policy. Note how the output is now using the
`policy` keyword instead of the `address` keyword. The policy in the
transaction below is a simple 2 of 2 multisig specified using
miniscript.

```ruby
@multisig_tx = spend inputs: [
                       { tx: coinbase_tx, vout: 0, script_sig: 'p2wpkh:bob', sighash: :all}
                     ],
                     outputs: [
                       {
                         policy: 'thresh(2,pk($alice),pk($bob))',
                         amount: 49.999.sats
                       }
                     ]
```

The `sighash: :all` directive is optional. By default the DSL uses
sighash ALL, but I show this here to point out that we can provide
sighash type here.

We can use any other policy and here's another example with a policy
that requires a spending condition with 2 of 2 multisig or an claim
after a CSV timelock.


```ruby
@alice_boarding_tx = transaction inputs: [
                                   { tx: coinbase_tx, vout: 0, script_sig: 'p2wpkh:bob', sighash: :all }
                                 ],
                                 outputs: [
                                   {
                                     policy: 'or(99@thresh(2,pk($alice),pk(bob)),and(older(10),pk($bob_timelock)))',
                                     amount: 49.999.sats
                                   }
                                 ]

```

To spend the transaction, we introduce a `csv` keyword. The following
is an example of a transaction spending from the timelock path of the
above transaction.

```ruby
@spend_tx = transaction inputs: [
                          { tx: @alice_boarding_tx,
                            vout: 0,
                            script_sig: 'p2wpkh:asp_timelock nulldummy nulldummy nulldummy',
                            csv: 10 }
                        ],
                        outputs: [
                          {
                            address: 'p2wpkh:asp',
                            amount: 49.998.sats
                          }
                        ]
```

Note how we specified `nulldummy` to generate the correct
`script_sig`. Also, the use of the `CSV` keyword to setup sequence
values as required.

We see here how the DSL hides the complications of constructing
bitcoin transactions by providing a high level language to build
transactions.


## Bitcoin node interactions

All the part about building transactions is fine. However, the sweet
part is that we can interact with a bitcoin node to submit the
transactions generated and then query the node for the state of the
transactions. In fact, the entire range of json-rpc API for bitcoin is
directly available in the DSL.

In this post, we only focus on the most often used commands and the
abstractions the DSL provides over those.

1. Broadcast transactions
1. Verify signatures of a transaction
1. Assert that the mempool will accept the transaction
1. Assert that a certain transaction is confirmed at a certain height

Here's how you do all of the above.

### Broadcast transactions

```ruby
broadcast @alice_boarding_tx
```

### Verify signatures for a transaction

```ruby
verify_signature for_transaction: @alice_boarding_tx,
                 at_index: 0,
                 with_prevout: [coinbase_tx, 0]

```

### Assert mempool will accept a transaction

```ruby
assert_mempool_accept @alice_boarding_tx
```

### Assert a transaction is confirmed

```ruby
assert_confirmed transaction: @alice_boarding_tx
```

## Next Steps

Some of the initial goals for the DSL have already been
accomplished. Namely, an ability to describe transactions in a high
level language and then submit those transactions to a bitcoin node as
well as query the bitcoin node.

Some nice features that I am working on include:

1. Generating coinbase to a miniscript policy.
2. Abstractions over taproot so that it is easy to build taproot transactions using an abstract DSL.
3. Provide highlevel constructs to tweak keys and generate musig and threshold signatures.
