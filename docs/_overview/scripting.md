---
layout: page
title: Bitcoin Scripts
nav_order: 2
---

# Bitcoin Scripts

The DSL provides flexibility in how locking and unlocking script are
specified.

---

## Script

To provide the most flexibility, the DSL support Script provided as an
interpolated string. Developers can drop in variable names prefixed by
a command to generate signatures and/or hashes.

For example, the script below will replace `hash160:$alice` with a
signature for the transaction using the public key referenced by the
variable `@alice`.

```ruby
'OP_DUP OP_HASH160 hash160:$alice OP_EQUALVERIFY OP_CHECKSIG'
```

There are a number of commands that are interpolated in script, see
the [Script interpolation](/reference#script_interpolation) section
for list of commands supported.

## Outputs: Miniscript Policy 

For generating output scripts, the DSL support miniscript Policy to
allow for flexible contract construction.


For example, the policy
`'or(99@thresh(2,pk($alice),pk($asp)),and(older(10),pk($asp_timelock)))'`
is processed by rust-miniscript after `$alice`, `$asp` and
`$asp_timelock` have been replaced by hex formatted public keys.

There are a number of commands that are interpolated in script, see
the [Interpolated miniscript
policy](/reference#interpolated-miniscript-policy) section of the
reference for details.
