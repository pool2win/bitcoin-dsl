# Consensus as a value

This is the most important design decision of the DSL: consensus is a value, not code in an interpreter loop. A consensus value holds these items:

- A list of **named rules** in order. Each rule has a scope (`tx` or `input`), a doc string and a check.
- A **table of opcodes**, with the byte as the key.
- A **sighash selector** for each spend version: `v0` for BIP143 and `v1` for BIP341.
- **Parameters**: the coinbase maturity, the halving interval, the subsidy and the block spacing.

Validation runs the rules in order. It sends each rule and each opcode that runs to a trace hook. A rejection always gives the name of the rule that failed. [Consensus rules](../reference/rules.md) lists the rules of `bitcoin`.

## Opcodes and bytes

Scripts use opcode names, but the DSL identifies opcodes by their byte. A global registry maps each name and each alias to its byte. For example, `cltv` and `nop2` are `0xb1`, `csv` and `nop3` are `0xb2`, and `ctv` and `nop4` are `0xb3`. Each consensus value sets the function of each byte.

Thus one script can run a NOP on one chain and an upgraded opcode on a different chain. On `bitcoin`, the `ctv` of a vault runs as `nop4`, and `explain` shows `(op ctv #:as nop4 …)`. The `bitcoin` table has `NOP1` and `NOP4` to `NOP10` as upgradable NOPs. See [Opcodes](../reference/opcodes.md).

## Make a rule set

`define-consensus` makes a new value from a list of changes to a parent:

```racket
(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))

(define-consensus experiment #:extends ctv-rules
  #:params  (set coinbase-maturity 50)
  #:rules   (remove duplicate-inputs)
            (add my-rule)
            (replace value-balance my-balance-rule)
  #:sighash (add v2 my-selector))
```

| Change | Effect |
|---|---|
| `(upgrade old #:to new)` | Replaces the upgradable NOP `old` with the known proposal opcode `new`. The two opcodes have the same byte. |
| `(add r)` | Adds the rule `r` at the end. Its name must be new. |
| `(remove name)` | Removes a rule. |
| `(replace name r)` | Puts new behavior in the same position. `r` must have the name that it replaces. |
| `(set key value)` | Changes a parameter. The parameter must exist. |
| `(add version selector)` | Adds a sighash version. |

The DSL refuses an incorrect change and gives a clear error. These are examples of incorrect changes:

- An upgrade of an opcode that is not an upgradable NOP.
- An upgrade to an unknown opcode.
- The removal of a rule that does not exist.
 The DSL does not evaluate the opcode names. A name identifies a NOP position or a registered proposal opcode.

A rule is `(rule name scope doc check)`. The `check` takes the validation context. It returns `#f` if the rule passes, or a failure with details. `private/consensus.rkt` contains the rules and gives examples.

## Compare rule sets

```racket
(diff-consensus bitcoin ctv-rules)    ; => ((opcode #xb3 nop4 -> ctv))
(diff-consensus ctv-rules experiment)
; => ((rule - duplicate-inputs) (rule + my-rule) (rule ~ value-balance)
;     (param coinbase-maturity 100 -> 50) (sighash + v2))
```

Replay uses the same differences to find the steps that a target node can check. See [Conformance replay](conformance.md).

## Audit a lock against a chain

`audit` returns the places where a chain does not enforce the scripts of a lock as they are written:

```racket
(audit (vault) #:on mainnet)  ; => ((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))
(audit (vault) #:on signet)   ; => ()
```

It gives a warning for these problems:

- An opcode that runs as an upgradable NOP.
- An opcode that the chain does not define.
- An OP_SUCCESS byte in tapscript. The model does not have OP_SUCCESS.

## Proposal opcodes

A proposal opcode is a usual opcode value with a registered name. Thus `define-consensus` can upgrade a NOP to it. `private/proposals.rkt` contains CTV (BIP119):

- `(template #:outputs (list (output …)) …)` makes a template. Its hash commits to the version, the locktime, the number of inputs, the sequences, the outputs and the input index. The BIP119 scriptSig hash does not occur, because the model has no scriptSigs.
- The policy fragment `(ctv t)` locks a coin to the template `t`.
- The opcode compares the template with the tx that spends the coin. If they are different, it fails with `ctv-template-mismatch`. The failure gives the different `#:fields`, with `#:expected` and `#:got` values.
- Proposal opcodes get the tx that spends the coin through general context fields: `tx`, `index` and `spent-coins`. Thus CSFS, TXHASH or CAT can use the same method.

The tests compare the real BIP119 hash with the test vectors of Bitcoin Inquisition.
