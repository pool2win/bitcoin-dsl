---
layout: page
title: Lightning Contracts
nav_order: 1
has_children: true
---

Lightning contracts make a good example for showing how the DSL is
useful.

We need the following transactions that are in various states of being
signed and are sometimes spendable, sometimes not.

1. Funding transactions
2. Redeem transactions
3. HTLC contracts
4. Cooperative close of channels
5. Forced close of channels


Things get even more interesting as there are conversations around
anchor transactions.

There is also some discussion around the use of various covenants that
can help simplify these transactions. The DSL can support these
covenants as long as the bitcoin node supports the required opcodes.

