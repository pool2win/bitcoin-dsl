# Consensus as a value

The structural decision behind the DSL: consensus is a value, not code inside an interpreter loop. A consensus value holds

- an ordered list of **named rules**, each with a scope (`tx` or `input`), a doc string and a check;
- an **opcode table** keyed by byte;
- a **sighash selector** per spend version (`v0` for BIP143, `v1` for BIP341);
- **parameters** (coinbase maturity, halving interval, subsidy, block spacing).

Validation walks the rules in order and reports every rule and opcode that runs to a trace hook. A rejection always names the rule that failed. The full list for `bitcoin` is in [Consensus rules](../reference/rules.md).

## Opcodes by byte

Scripts use opcode names, but opcodes are identified by byte. A global registry maps every name and alias to its byte (`cltv`/`nop2` = `0xb1`, `csv`/`nop3` = `0xb2`, `ctv`/`nop4` = `0xb3`), and each consensus value decides what that byte does. The same script can run a NOP on one chain and an upgraded opcode on another: a vault's `ctv` runs as `nop4` on `bitcoin`, and `explain` shows it as `(op ctv #:as nop4 …)`. The `bitcoin` table includes `NOP1` and `NOP4`–`NOP10` as upgradable NOPs. See [Opcodes](../reference/opcodes.md).

## Composing rule sets

`define-consensus` builds a new value as a list of changes to a parent:

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

| Change | Meaning |
|---|---|
| `(upgrade old #:to new)` | Replace the upgradable NOP `old` with the known proposal opcode `new` (same byte). |
| `(add r)` | Append rule `r`; its name must be new. |
| `(remove name)` | Drop a rule. |
| `(replace name r)` | New behaviour in the same slot; `r` must have the name it replaces. |
| `(set key value)` | Change a parameter that exists. |
| `(add version selector)` | Add a sighash version. |

Bad changes are refused with a clear error: upgrading something that is not an upgradable NOP, an unknown opcode, removing a rule that does not exist. Opcode names are not evaluated: they name a NOP slot and a registered proposal opcode.

A rule is `(rule name scope doc check)`, where `check` takes the validation context and returns `#f` when the rule passes or a failure with details. Rules live in `private/consensus.rkt`; see it for examples.

## Comparing rule sets

```racket
(diff-consensus bitcoin ctv-rules)    ; => ((opcode #xb3 nop4 -> ctv))
(diff-consensus ctv-rules experiment)
; => ((rule - duplicate-inputs) (rule + my-rule) (rule ~ value-balance)
;     (param coinbase-maturity 100 -> 50) (sighash + v2))
```

Replay uses the same diff to decide which steps a target node can check (see [Conformance replay](conformance.md)).

## Auditing a lock against a chain

`audit` reports where a lock's scripts would not be enforced as written on a chain:

```racket
(audit (vault) #:on mainnet)  ; => ((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))
(audit (vault) #:on signet)   ; => ()
```

It warns about opcodes that run as upgradable NOPs, opcodes the chain does not define, and OP_SUCCESS bytes in tapscript (not modelled).

## Proposal opcodes

A proposal opcode is an ordinary opcode value registered by name so `define-consensus` can upgrade to it. CTV (BIP119) lives in `private/proposals.rkt`:

- `(template #:outputs (list (output …)) …)` builds a template; its hash commits to version, locktime, input count, sequences, outputs and input index (BIP119's scriptSig hash never appears, as the model has no scriptSigs).
- The policy fragment `(ctv t)` locks a coin to a template.
- The opcode compares the template with the spending transaction and fails with `ctv-template-mismatch`, naming the differing `#:fields` with `#:expected` and `#:got` values.
- Proposal opcodes see the spending transaction through generic context fields (`tx`, `index`, `spent-coins`), so CSFS, TXHASH or CAT can be added the same way.

The real BIP119 hash is checked against Bitcoin Inquisition's test vectors.
