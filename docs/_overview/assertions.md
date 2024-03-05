---
layout: page
title: Assertions
nav_order: 5
---

# Assertions

Assertions help a contract developer check progress of a contract
along the execution path they are exploring.

---

Without assertions the contract developer has to verify the state of
execution at each step.

With assertions, the developer can verify if a transaction has been
spent, is spendable, is confirmed. They can also assert the current
chain height, etc.

Assertions are commands that strive to remain intuitive. For example
`assert_mempool_accept` asserts the transaction argument will be
accepted by the mempool.

```ruby
assert_mempool_accept @alice_tx
```

All the available assertions are documented under
[Assertions](/reference#assertions) in the Reference page.
