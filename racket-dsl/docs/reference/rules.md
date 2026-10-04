<!-- docs/gen-reference.rkt makes this page from the describe registry. Do not edit it. -->

# Consensus rules

This page lists the rules of the `bitcoin` consensus value, in the order that validation runs them. The `#:rule` of a rejection is one of these names, or one of the script rules below.

| Rule | Scope | Description |
|---|---|---|
| `inputs-nonempty` | tx | A transaction spends at least one coin. |
| `outputs-nonempty` | tx | A transaction creates at least one output. |
| `output-range` | tx | Every output amount, and their total, lies between 0 and 21M BTC. |
| `duplicate-inputs` | tx | No coin is spent twice by one transaction. |
| `locktime-final` | tx | A transaction with nLockTime set waits until a block above that height, unless every input's nSequence is final. |
| `input-exists` | input | Each input spends an unspent coin on this chain. |
| `coinbase-maturity` | input | A coinbase output is spendable once it is 100 blocks deep. |
| `value-balance` | tx | The sum of the inputs is equal to or more than the sum of the outputs. The difference is the fee. |
| `sequence-lock` | input | BIP68: an input whose nSequence encodes a relative lock waits that many blocks after its coin confirmed. |
| `witness-script` | input | Each input's witness satisfies the script of the coin it spends. |

## Script rules

A failure of witness-script gives the name of a more specific rule: one of these rules, or the opcode that failed (see opcodes).

| Rule | Description |
|---|---|
| `bad-opcode` | The script uses an opcode that this consensus does not define. |
| `cleanstack` | A segwit script must stop with exactly one item on the stack. |
| `eval-false` | The script stopped with false on top of the stack, for example after a CHECKSIG with a signature that is not valid. #:cause gives the cause. |
| `key-path-sig` | A taproot spend through the key path must have a valid signature by the internal key. #:cause gives the cause. |
| `stack-underflow` | An opcode needed more stack items than the stack had. |
| `taproot-commitment` | The control block and the leaf script do not commit to the taproot output key. |
| `unbalanced-conditional` | The IF, ELSE and ENDIF opcodes do not match. |
| `unsupported` | The model does not have this feature yet, for example locks based on time. |
| `unsupported-spend` | The model does not have this type of output yet. |
| `witness-program-mismatch` | The witness does not agree with the witness program of the output: the number of items is wrong, or the hash of the script is not the program. |

## Proposal rules

| Rule | Opcode | Description |
|---|---|---|
| `ctv-template-mismatch` | `ctv` | The tx that spends the coin does not agree with the CTV template. #:fields gives the fields that are different. #:expected and #:got give the values of the template and of the tx. |
