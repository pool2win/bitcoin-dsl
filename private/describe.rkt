#lang racket/base
;; Self-description for agents: (describe) and (describe topic).
;;
;; Topics are a form name, rules, opcodes, state or forms. Everything is
;; returned as data; strings are the human-readable parts.

(require racket/list
         "consensus.rkt"
         "script.rkt"
         "compose.rkt"
         "session.rkt")

(provide describe)

;; (name group signature doc), in the order describe lists them.
;; (name group signature doc), in the order describe lists them. The docs
;; are in ASD-STE100 Simplified Technical English (see AGENT.md).
(define forms
  '((chain definition "(chain name #:rules consensus)"
           "Defines a chain with a new genesis block at height 0. Give chains names such as `mainnet` and `signet`, because `btc` is the amount constructor. The `bitcoin` rules use regtest parameters: a subsidy of 50 BTC that halves every 150 blocks, and a coinbase maturity of 100 blocks.")
    (keys definition "(keys name ...)"
          "Binds each name to a key with that name. Keys are symbolic. Replay derives real keys from the names.")
    (secret value "(secret 'name)"
            "Makes a hash preimage. Use it with `(sha256 s)` in contracts, and reveal it with `#:reveal`.")
    (contract definition "(contract name (param ...) policy)"
              "Defines a function that makes a P2WSH lock from the parameters. The policy forms are `(pk k)`, `(sha256 s)`, `(older blocks)`, `(after height)`, `(ctv template)`, `(and p ...)`, `(or arm ...)` and `(thresh k (pk a) ...)`. An arm of `or` can have a label, `[label policy]`, and the label is the name of the spend path. `(older n)` counts the block of the coin: after the block that funds the coin, a `try` sees age 1, thus mine n-1 more blocks.")
    (define-tx definition "(define-tx name #:inputs ([coin input-option ...] ...) #:outputs ([label lock amount] ...))"
               "Builds and signs a tx. It binds the tx to the name, and it binds each output label to the coin of that output as a top-level definition. A later `define-tx` with the same label binds the label again. The input options are the same as for `input`, for example `[cb #:sign alice #:sighash '(all anyonecanpay)]`.")
    (btc value "(btc 49.99)" "Makes an amount in BTC. The amount is kept as an exact number of satoshis.")
    (sats value "(sats 1000)" "Makes an amount in satoshis.")
    (wpkh value "(wpkh key)" "Makes a P2WPKH lock.")
    (tr value "(tr key #:leaves (list contract-lock ...))"
        "Makes a taproot lock: a key path for the key, and one script leaf for each contract. The branches are `key`, then the leaf name or `leaf/path`.")
    (input value "(input coin #:sign key-or-list #:path 'branch #:reveal secret-or-list #:sighash flags #:sequence n)"
           "Makes the specification of one input. `#:path` selects a branch and sets nSequence and nLockTime. A signature or preimage that you do not give becomes an empty witness item. `#:sighash` is `'all`, `'none` or `'single`, or a list with `anyonecanpay`, for example `'(all anyonecanpay)`. Taproot also has `'default`.")
    (output value "(output 'label lock amount)" "Makes the specification of one output.")
    (output-of query "(output-of tx index)" "Returns the coin at that output index.")
    (out query "(out tx 'label)" "Returns the coin with that label.")
    (mine session "(mine n #:on chain #:to key)"
          "Mines n blocks. The first block includes the mempool. It returns the list of coinbase coins; put the call in `void` to discard them. Without `#:to`, the coinbases pay an anonymous miner, and no user key can spend them. Coinbases mature after 100 blocks. The subsidy halves every 150 blocks.")
    (spend value "(spend coin-or-inputs #:sign key-or-list #:path 'branch #:reveal s #:sighash flags #:sequence n #:locktime n #:name 'name #:outputs (list (output 'label lock amount) ...))"
           "Builds and signs a tx as an expression, for `try` and for the REPL. Use `out` to get its outputs. `#:path` sets nSequence and nLockTime for the branch, thus `#:sequence` and `#:locktime` are not usually necessary. To spend more than one coin, give a list of `(input ...)` specifications.")
    (add-input value "(add-input tx coin #:sign key ...)  ; returns a tx named <name>+input"
               "Adds an input at the end of the tx and signs only that input. The other signatures stay valid only if their sighash does not commit to the inputs.")
    (try session "(try tx)" "Validates the tx against the chain and the mempool. It does not change the state. It returns `accepted` or `rejected`.")
    (broadcast session "(broadcast tx)" "Validates the tx. If the tx is accepted, it goes into the mempool. It returns `accepted` or `rejected`.")
    (confirm session "(confirm tx)" "Broadcasts the tx. If the tx is accepted, it mines one block with the coinbase to the anonymous miner. This spends the inputs permanently. To keep alternatives available, use `try` or `snapshot` first.")
    (confirmed? query "(confirmed? tx)" "Returns true if the tx is in a block.")
    (height query "(height #:on chain)" "Returns the height of the chain tip. If the session has only one chain, you can omit `#:on`.")
    (utxos query "(utxos #:on chain #:spendable-by key #:locked-by lock)"
           "Returns the confirmed coins in order of height, then outpoint. If the session has only one chain, you can omit `#:on`.")
    (fee query "(fee tx)" "Returns the inputs minus the outputs. A negative fee means that the outputs are more than the inputs. `try` rejects such a tx with `value-balance`.")
    (branches query "(branches coin)" "Returns the spend paths of the coin, each with the items that it needs.")
    (last-trace query "(last-trace)" "Returns the trace of the most recent `try` or `broadcast`.")
    (explain query "(explain trace-or-id)"
             "Returns a trace as data: each rule and each opcode that ran, in order. Stacks show the top item first. The rule that failed has its doc.")
    (snapshot session "(snapshot)" "Captures the chains and the scenario log. It does not capture Racket definitions.")
    (restore session "(restore snapshot)" "Puts the chains and the log back to a snapshot.")
    (sig-of query "(sig-of tx input #:key key)" "Returns the signature on an input.")
    (commits query "(commits sig)" "Returns the fields that a signature commits to. The list changes with the spend version and the flags. `(describe 'sighash)` gives the field names.")
    (free-fields query "(free-fields tx)" "Returns the edits from a fixed catalogue that keep every signature valid: `(inputs append)`, `(inputs remove-others)`, `(outputs append)`, `(output ref amount)`, `(output ref lock)`, `(input i sequence)`, `version` and `locktime`.")
    (mutate query "(mutate tx path value)"
            "Applies an edit and returns the signatures that the edit breaks, with the fields that changed. The paths are the same as for `edit`.")
    (edit value "(edit tx path value)"
          "Returns the tx with one field changed. The witnesses do not change. The paths are `version`, `locktime`, `(input i sequence)`, `(output ref amount)`, `(output ref lock)`, `(inputs append)` with a coin, `(inputs remove i)`, `(outputs append)` with an `(output ...)` and `(outputs remove ref)`. `ref` is an output label or index. `i` is an input index.")
    (scenario-log query "(scenario-log)" "Returns the log of chain, mine, try and broadcast events, the oldest first.")
    (replay conformance "(replay (scenario-log) #:targets (hash 'mainnet (regtest) 'signet (regtest #:build 'inquisition)))"
            "Replays the log against new regtest nodes, one node for each chain. Each step is `confirmed` (the node agrees on consensus), `disagree` or `unverified`. For an unverified step, `#:reason` gives the cause: no target, a rule that the target runs differently (`(model-only-rule ctv)`), a step that depends on an unverified step, or a value that replay cannot lower. A confirmed step with `#:mempool-only` is a tx that the mempool of the node refused because of policy, but that a block can include. Read a run with `summary`, `disagreements`, `unverified-steps`, `run-steps` and the `step-` accessors.")
    (regtest conformance "(regtest #:build 'core|'inquisition #:bitcoind path)"
             "Makes a replay target. `core` runs `bitcoin` with the `bitcoind` on PATH. `inquisition` runs `bitcoin` plus CTV (the consensus value `inquisition`). Replay finds it through `BITCOIN_INQUISITION` or at `~/projects/bitcoin-inquisition/build/bin/bitcoind`.")
    (unverified-steps conformance "(unverified-steps run)" "Returns the steps that replay could not check, each with its `#:reason`.")
    (run-steps conformance "(run-steps run)" "Returns all the steps of a run as `(status #:step n event detail)`. Read them with `step-n`, `step-status`, `step-event` and `step-detail`.")
    (summary conformance "(summary run)" "Returns the number of confirmed, disagree and unverified steps.")
    (disagreements conformance "(disagreements run)" "Returns the steps where the node and the model do not agree.")
    (define-consensus consensus "(define-consensus name #:extends parent #:opcodes (upgrade nop4 #:to ctv) #:rules (add r) (remove n) (replace n r) #:params (set k v) #:sighash (add version selector))"
                      "Defines a consensus value as a list of changes to a parent. For example, a soft fork changes an upgradable NOP to a proposal opcode (the known proposal is `ctv`). Give the value to `chain` with `#:rules`. The opcode names are not evaluated.")
    (diff-consensus consensus "(diff-consensus a b)"
                    "Returns the changes from a to b: `(opcode #xb3 nop4 -> ctv)`, `(rule + name)`, `(rule - name)`, `(rule ~ name)`, `(param k old -> new)` and `(sighash + version)`.")
    (template consensus "(template #:outputs (list (output ...)) #:version 2 #:locktime 0 #:inputs 1 #:sequences (...) #:index 0)"
              "Makes a CTV (BIP119) template: the tx that must spend a coin with the lock `(ctv template)`. The default values agree with `spend` and `define-tx`.")
    (audit consensus "(audit lock #:on chain)"
           "Returns the places where a chain does not enforce the scripts of a lock as they are written, for example `(warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4)`. It returns `'()` if there is no problem.")
    (sighash-search query "(sighash-search tx #:goal (can (add-input) ...) #:keep (fixed (outputs all) ...) #:over '(wpkh tr-key tr-script))"
                    "Returns each `(spend-type flags)` with which the signers can sign so that the goal edits are free and the kept fields are not free. The goal words are `add-input`, `remove-inputs`, `add-output`, `change-outputs`, `change-version` and `change-locktime`. The keep words are `(outputs all)`, `(inputs all)`, `(output ref)`, `version` and `locktime`.")
    (sighash-matrix conformance "(sighash-matrix #:spend-types '(wpkh tr-key tr-script) #:flags 'all #:target (regtest))"
                    "Checks the verdict of the model against a real node for each spend type, flag set and edit. It runs in a scratch session. It returns rows `(status #:type #:flags #:edit #:model ...)`.")
    (describe query "(describe) (describe 'topic)" "Gives this help. The topics are `example`, a form name, a rule name, `rules`, `opcodes`, `state` and `forms`.")
    (reset-session! session "(reset-session!)" "Removes all chains, traces and the log.")))

(define results-doc
  '("try and broadcast return (accepted #:chain c #:tx t #:step n #:trace id) or"
    "(rejected #:chain c #:rule r #:input i <rule details> #:step n #:trace id)."
    "Use accepted?, rejected?, rejected-rule, rejected-input and (result-detail r 'need) to read them."))

(define conventions
  '("Results are data. Queries return values. They do not print."
    "The DSL does not select coins for you. Coins come from mine or from outputs with labels."
    "Each rejection gives the name of a rule. (describe 'rule-name) documents the rule, and explain shows the steps to it."
    "The crypto is symbolic. A signature contains the fields that it commits to. Replay lowers all values to real bytes."))

(define tips
  '("try tests a tx and does not change the state. confirm spends the inputs permanently."
    "Make a snapshot before you try alternatives. Use restore to return to the snapshot."
    "To mature coinbases, use (void (mine 100 #:on chain)). Without #:to, the coins go to an anonymous miner, and your keys keep only their own coins."
    "Mine all the coins that you need early, because the subsidy halves every 150 blocks."))

;; What each sighash flag commits to, and the field names commits uses.
(define sighash-doc
  '((flags "#:sighash is 'all (the default for segwit v0), 'none or 'single. Each one can have anyonecanpay in a list, for example '(all anyonecanpay). 'default is the taproot default, and it commits to the same fields as all.")
    (segwit-v0 "BIP143. A signature always commits to version, the outpoint and sequence of its input, the script and amount of its prevout, and locktime. Without anyonecanpay, it also commits to (inputs outpoints). With all and without anyonecanpay, it also commits to (inputs sequences). all commits to (outputs all). single commits to (own-output), or to no output if there is no output at the index of the input. none commits to no output.")
    (taproot "BIP341. A signature always commits to version, locktime and spend-type. Without anyonecanpay, it commits to (inputs outpoints), (inputs amounts), (inputs spks), (inputs sequences) and (own-input index). With anyonecanpay, it commits to the outpoint, amount, spk and sequence of its own input. all and default commit to (outputs all). single commits to (own-output), and it is not valid if there is no such output. none commits to no output. A script path also commits to (own-leaf) and codesep-position.")
    (fields "The own- names refer to the input that signs. (inputs ...) and (outputs all) include each input or output, thus a new or removed input or output changes them.")
    (queries "commits lists the fields of a signature. free-fields lists the edits that no signature commits to. mutate applies an edit and shows which signatures break, and on which fields. A rejection for commitment-mismatch has the same #:fields.")))

(define example
  '((chain mainnet #:rules bitcoin)
    (keys alice bob)
    (define cb (first (mine 1 #:on mainnet #:to alice)))
    (void (mine 100 #:on mainnet))
    (define-tx pay
      #:inputs ([cb #:sign alice])
      #:outputs ([to-bob (wpkh bob) (btc 49.99)]
                 [change (wpkh alice) (btc 0.009)]))
    (confirm pay)
    (utxos #:spendable-by bob)
    (fee pay)))

;; c is the consensus value rules and opcodes describe (bitcoin by default).
(define (describe [topic #f] [c bitcoin])
  (cond
    [(not topic)
     (list (list 'purpose "Model Bitcoin chains, transactions and scripts. Then replay them against real nodes.")
           (cons 'conventions conventions)
           (cons 'results results-doc)
           (cons 'tips tips)
           (cons 'example example)
           (cons 'forms (for/list ([g '(definition value consensus session query conformance)])
                          (cons g (for/list ([f (in-list forms)] #:when (eq? (second f) g)) (third f)))))
           (list 'topics "Give the name of a form, rule, opcode, group (definition value consensus session query conformance) or consensus value (for example bitcoin). Other topics: rules, opcodes, sighash, state, example.")
           (list 'consensus-values (registered-consensus-names)
                 "In eval, these names are bound: bitcoin, inquisition (with bitcoin/conform) and the values that you define."))]
    [(memq topic '(definition value consensus session query conformance))
     (for/list ([f (in-list forms)] #:when (eq? (second f) topic)) (list (first f) (third f) (fourth f)))]
    [(eq? topic 'sighash) sighash-doc]
    [(eq? topic 'example) example]
    [(eq? topic 'forms) (map (λ (f) (list (first f) (third f))) forms)]
    [(eq? topic 'rules)
     (append
      (for/list ([r (in-list (consensus-rules c))])
        (list (rule-name r) '#:scope (rule-scope r) (rule-doc r)))
      (list (list 'within-witness-script
                  "A failure of witness-script gives the name of a more specific rule: one of these rules, or the opcode that failed (see opcodes)."))
      (for/list ([name (in-list (sort (hash-keys script-failure-docs) symbol<?))])
        (list name (hash-ref script-failure-docs name))))]
    [(eq? topic 'opcodes)
     (for/list ([oc (in-list (sort (hash-values (consensus-opcodes c)) < #:key opcode-byte))])
       (list (opcode-name oc) '#:byte (opcode-byte oc) (opcode-doc oc)))]
    [(eq? topic 'state) (session-summary)]
    [(assq topic forms) => (λ (f) (list (first f) '#:usage (third f) '#:doc (fourth f)))]
    [(registered-consensus topic)
     => (λ (rc) (list topic
                      '#:parent (and (consensus-parent rc) (consensus-name (consensus-parent rc)))
                      '#:changes (if (consensus-parent rc) (diff-consensus (consensus-parent rc) rc) '())
                      "For more data, call describe with rules or opcodes and give this consensus value as the second argument."))]
    [(known-opcode? topic)
     => (λ (_) (let ([oc (known-opcode topic)])
                 (list topic '#:byte (opcode-byte oc) '#:proposal (opcode-doc oc)
                       '#:failures (hash->list (opcode-failures oc)))))]
    [(for/or ([name (in-list (registered-consensus-names))]) (failure-doc (registered-consensus name) topic))
     => (λ (doc) (list topic doc))]
    [(for/or ([name (in-list (list 'ctv))] #:when (known-opcode? name))
       (hash-ref (opcode-failures (known-opcode name)) topic #f))
     => (λ (doc) (list topic doc))]
    [else (list 'unknown-topic topic "Try (describe) for the list of forms and topics.")]))
