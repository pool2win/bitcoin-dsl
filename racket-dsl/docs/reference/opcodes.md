<!-- docs/gen-reference.rkt makes this page from the describe registry. Do not edit it. -->

# Opcodes

The DSL identifies opcodes by their byte. Scripts use names. Aliases such as `cltv`/`nop2`, `csv`/`nop3` and `ctv`/`nop4` are names for the same byte. Each consensus value sets the function of each byte.

## In `bitcoin`

| Opcode | Byte | Description |
|---|---|---|
| `if` | `0x63` | Run the next branch if the top item is true. |
| `notif` | `0x64` | Run the next branch if the top item is false. |
| `else` | `0x67` | Switch to the other branch. |
| `endif` | `0x68` | End a conditional. |
| `verify` | `0x69` | Fail unless the top item is true. |
| `drop` | `0x75` | Remove the top item. |
| `dup` | `0x76` | Duplicate the top item. |
| `swap` | `0x7c` | Swap the top two items. |
| `size` | `0x82` | Push the size of the top item. The item stays on the stack. |
| `equal` | `0x87` | Push true if the top two items are equal, else push false. |
| `equalverify` | `0x88` | Fail unless the top two items are equal. |
| `add` | `0x93` | Replace the top two numbers with their sum. |
| `sha256` | `0xa8` | Replace the top item with its SHA256. |
| `hash160` | `0xa9` | Replace the top item with its HASH160. |
| `checksig` | `0xac` | Check a signature against a pubkey and the sighash. |
| `checksigverify` | `0xad` | CHECKSIG, then fail unless it succeeded. |
| `nop1` | `0xb0` | Does nothing; reserved for soft-fork upgrades. |
| `cltv` | `0xb1` | BIP65: fail unless nLockTime has reached the top item. |
| `csv` | `0xb2` | BIP112: fail unless this input's nSequence encodes at least the top item. |
| `nop4` | `0xb3` | Does nothing; reserved for soft-fork upgrades (BIP119 proposes CTV). |
| `nop5` | `0xb4` | Does nothing; reserved for soft-fork upgrades. |
| `nop6` | `0xb5` | Does nothing; reserved for soft-fork upgrades. |
| `nop7` | `0xb6` | Does nothing; reserved for soft-fork upgrades. |
| `nop8` | `0xb7` | Does nothing; reserved for soft-fork upgrades. |
| `nop9` | `0xb8` | Does nothing; reserved for soft-fork upgrades. |
| `nop10` | `0xb9` | Does nothing; reserved for soft-fork upgrades. |

## Proposal opcodes

`define-consensus` can change an upgradable NOP to one of these opcodes.

| Opcode | Byte | Description |
|---|---|---|
| `ctv` | `0xb3` | BIP119 CHECKTEMPLATEVERIFY: fail if the tx that spends the coin does not agree with the template hash on top of the stack. |
