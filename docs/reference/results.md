# Results and traces

Each value that an agent uses for decisions has a fixed shape. It prints in keyword form, thus you can read it back as data.

## Validation results

`try`, `broadcast` and `confirm` return one of these values:

```racket
(accepted #:chain mainnet #:tx #<tx pay 20a17961> #:step 4 #:trace 1)

(rejected #:chain mainnet #:rule coinbase-maturity #:input 0
          #:need 100 #:have 51 #:step 5 #:trace 2)
```

| Field | Description |
|---|---|
| `#:chain` | The chain where the DSL validated the tx. |
| `#:rule` | The rule that failed: a [consensus rule](rules.md), a script rule or an opcode. |
| `#:input` | The input index, for rules with the scope `input`. |
| Rule details | Details for each rule, for example `#:need` and `#:have`, `#:outpoint`, `#:cause`, `#:fields`, `#:expected` and `#:got`. |
| `#:step` | The position of this event in the scenario log. |
| `#:trace` | The trace id, for `explain`. |

Use these accessors to read a result: `accepted?`, `rejected?`, `rejected-rule`, `rejected-chain`, `rejected-input` and `(result-detail r 'need)`.

These details occur frequently:

| Detail | Rules | Description |
|---|---|---|
| `#:need`, `#:have` | `coinbase-maturity`, `sequence-lock`, `locktime-final`, `csv`, `cltv` | The value that the rule must have, and the value that the tx has. |
| `#:cause` | `eval-false`, `checksig`, `checksigverify`, `key-path-sig` | The cause of the signature failure: `empty-signature`, `not-a-signature`, `wrong-key`, `commitment-mismatch` or `single-without-output`. |
| `#:fields` | Commitment mismatches, `ctv-template-mismatch` | The committed fields that are different. |
| `#:expected`, `#:got` | `ctv-template-mismatch` | The values of those fields in the template and in the tx. |
| `#:reason` | `csv`, `cltv`, `witness-program-mismatch` | The check that failed. |

## Traces and `explain`

`(explain trace-or-id)` returns one entry for each rule and each opcode, in order. The stacks show the top item first.

```racket
(rule inputs-nonempty pass)
(rule input-exists #:input 0 pass)
(op if #:stack (#"" (sig alice (all))) #:=> ((sig alice (all))))
(op ctv #:as nop4 #:stack (…) #:=> (…))
(op checksig #:stack (…) #:fail checksig #:cause commitment-mismatch)
(rule witness-script #:input 0 fail #:as eval-false #:cause empty-signature #:doc "…")
(rule sequence-lock #:input 0 fail #:need 144 #:have 1 #:doc "BIP68: …")
```

- `#:as` on an `op` entry gives the opcode that the chain ran for the name in the script. For example, `ctv` runs as `nop4` on `bitcoin`.
- `#:as` on a `rule` entry that failed gives the more specific rule of the failure. For example, `eval-false` occurs in `witness-script`.
- `#:doc` gives the documentation of the rule that failed.

`(last-trace)` returns the most recent trace. `trace-events` gives the events without a change.

## Other shapes

| Form | Returns |
|---|---|
| `branches` | `((claim #:needs ((sig bob) (preimage s1))) …)` |
| `commits` | A list of field names. |
| `free-fields` | A list of edits, for example `((inputs append) (inputs remove-others))`. |
| `mutate` | `(breaks ((sig alice 0 #:fields ((outputs all)))))`. Read it with `breaks-entries` and `intact?`. |
| `sighash-search` | `((wpkh (all anyonecanpay)) …)` |
| `diff-consensus` | `((opcode #xb3 nop4 -> ctv) (rule + name) (param k old -> new) …)` |
| `audit` | `((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4))` or `()` |
| `(describe 'state)` | `((chain mainnet #:rules bitcoin #:height 101 #:mempool 0 #:utxos 101) (log-steps 4) (traces 1))` |

## Replay results

`replay` returns a run. `(summary run)` gives `((confirmed n) (disagree n) (unverified n))`. `run-steps`, `disagreements` and `unverified-steps` give steps. Each step prints like this:

```racket
(confirmed #:step 4 (broadcast mainnet #<tx pay 20a17961> accepted))
(disagree #:step 5 (try …) (#:model accepted #:node (rejected "bad-txns-premature-spend-of-coinbase")))
(unverified #:step 13 (try signet …) (#:reason (model-only-rule ctv)))
```

Read a step with `step-n`, `step-status`, `step-event` and `step-detail`. A confirmed step can have `#:mempool-only reason`. This means that the mempool of the node refused the tx because of policy, but a block can include it.

`sighash-matrix` returns rows `(status #:type t #:flags f #:edit e #:model verdict …)` or `(unsupported #:type t)`.
