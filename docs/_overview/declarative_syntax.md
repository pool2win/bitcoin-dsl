---
layout: page
title: Declarative Sytax
nav_order: 1
---

# Declarative Syntax
The DSL specifies what needs to be done, not how. 

---

For example, to build a transaction, we should just say the scriptsig
is a `p2wpkh:bob` instead of making a series of imperative calls to
achieve the same goal.

Similarly, to add a OP_CSV constraint on a transaction output we
specify the `csv: NN` as a keyword option to the output.

Here's an example from the ARK transactions


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

## Sane defaults

The DSL by default assumes we only want to build SegWit transactions
and all contracts are wrapped in P2WSH.

If you need to build pre-segwit transactions, then you are out of luck
:)
