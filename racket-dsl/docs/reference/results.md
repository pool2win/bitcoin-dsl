# Results and traces

Every value an agent branches on has a fixed shape and prints in keyword form, so it reads back as data.

## Validation results

`try`, `broadcast` and `confirm` return one of:

```racket
(accepted #:chain mainnet #:tx #<tx pay 20a17961> #:step 4 #:trace 1)

(rejected #:chain mainnet #:rule coinbase-maturity #:input 0
          #:need 100 #:have 51 #:step 5 #:trace 2)
```

| Field | Meaning |
|---|---|
| `#:chain` | the chain the tx was validated on |
| `#:rule` | the rule that failed: a [consensus rule](rules.md), a script-level rule, or an opcode |
| `#:input` | the input index, for input-scoped rules |
| rule details | rule-specific, e.g. `#:need`/`#:have`, `#:outpoint`, `#:cause`, `#:fields`, `#:expected`/`#:got` |
| `#:step` | the position of this event in the scenario log |
| `#:trace` | the trace id, for `explain` |

Accessors: `accepted?`, `rejected?`, `rejected-rule`, `rejected-chain`, `rejected-input`, `(result-detail r 'need)`.

Common details:

| Detail | Seen on | Meaning |
|---|---|---|
| `#:need`, `#:have` | `coinbase-maturity`, `sequence-lock`, `locktime-final`, `csv`, `cltv` | what the rule requires and what the tx has |
| `#:cause` | `eval-false`, `checksig`, `checksigverify`, `key-path-sig` | why a signature failed: `empty-signature`, `not-a-signature`, `wrong-key`, `commitment-mismatch`, `single-without-output` |
| `#:fields` | commitment mismatches, `ctv-template-mismatch` | the committed fields that differ |
| `#:expected`, `#:got` | `ctv-template-mismatch` | the template's and the tx's values for those fields |
| `#:reason` | `csv`, `cltv`, `witness-program-mismatch` | which check failed |

## Traces and `explain`

`(explain trace-or-id)` returns one entry per rule and per opcode, in order. Stacks are shown top first.

```racket
(rule inputs-nonempty pass)
(rule input-exists #:input 0 pass)
(op if #:stack (#"" (sig alice (all))) #:=> ((sig alice (all))))
(op ctv #:as nop4 #:stack (…) #:=> (…))
(op checksig #:stack (…) #:fail checksig #:cause commitment-mismatch)
(rule witness-script #:input 0 fail #:as eval-false #:cause empty-signature #:doc "…")
(rule sequence-lock #:input 0 fail #:need 144 #:have 1 #:doc "BIP68: …")
```

- `#:as` on an `op` entry: the opcode the chain actually ran for the script's name (e.g. `ctv` running as `nop4`).
- `#:as` on a failing `rule` entry: the more specific rule the failure names (e.g. `eval-false` inside `witness-script`).
- `#:doc`: the failing rule's documentation.

`(last-trace)` returns the most recent trace; `trace-events` gives the raw events.

## Other shapes

| Form | Returns |
|---|---|
| `branches` | `((claim #:needs ((sig bob) (preimage s1))) …)` |
| `commits` | a list of field names |
| `free-fields` | a list of edit descriptors, e.g. `((inputs append) (inputs remove-others))` |
| `mutate` | `(breaks ((sig alice 0 #:fields ((outputs all)))))`; `breaks-entries` and `intact?` read it |
| `sighash-search` | `((wpkh (all anyonecanpay)) …)` |
| `diff-consensus` | `((opcode #xb3 nop4 -> ctv) (rule + name) (param k old -> new) …)` |
| `audit` | `((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))` or `()` |
| `(describe 'state)` | `((chain mainnet #:rules bitcoin #:height 101 #:mempool 0 #:utxos 101) (log-steps 4) (traces 1))` |

## Replay results

`replay` returns a run. `(summary run)` gives `((confirmed n) (disagree n) (unverified n))`; `run-steps`, `disagreements` and `unverified-steps` give steps, each printing as

```racket
(confirmed #:step 4 (broadcast mainnet #<tx pay 20a17961> accepted))
(disagree #:step 5 (try …) (#:model accepted #:node (rejected "bad-txns-premature-spend-of-coinbase")))
(unverified #:step 13 (try signet …) (#:reason (model-only-rule ctv)))
```

and readable with `step-n`, `step-status`, `step-event` and `step-detail`. A confirmed step may carry `#:mempool-only reason`: the node's mempool refused the tx by policy but a block would accept it.

`sighash-matrix` returns rows `(status #:type t #:flags f #:edit e #:model verdict …)`, or `(unsupported #:type t)`.
