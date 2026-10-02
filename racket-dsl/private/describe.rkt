#lang racket/base
;; Self-description for agents: (describe) and (describe topic).
;;
;; Topics are a form name, rules, opcodes, state or forms. Everything is
;; returned as data; strings are the human-readable parts.

(require racket/list
         "consensus.rkt"
         "script.rkt"
         "session.rkt")

(provide describe)

;; (name group signature doc), in the order describe lists them.
(define forms
  '((chain definition "(chain name #:rules consensus)"
           "Define a chain named name with a fresh genesis. Name chains mainnet, signet, etc.; btc is the amount constructor.")
    (keys definition "(keys name ...)"
          "Bind each name to a key of that name. Keys are symbolic; replay derives real keys from the names.")
    (secret value "(secret 'name)"
            "A hash preimage, used with (sha256 s) in contracts and revealed with #:reveal.")
    (contract definition "(contract name (param ...) policy)"
              "Define name as a function from params to a P2WSH lock. Policy forms: (pk k) (sha256 s) (older blocks) (after height) (and p ...) (or arm ...) (thresh k (pk a) ...). An or arm may be labelled [label policy]; labels name spend paths.")
    (define-tx definition "(define-tx name #:inputs ([coin input-option ...] ...) #:outputs ([label lock amount] ...))"
               "Build and sign a tx, bind it to name and bind each output label to that output's coin. Input options as for input.")
    (btc value "(btc 49.99)" "An amount in BTC, kept as exact satoshis.")
    (sats value "(sats 1000)" "An amount in satoshis.")
    (wpkh value "(wpkh key)" "A P2WPKH lock.")
    (tr value "(tr key #:leaves (list contract-lock ...))"
        "A taproot lock: key path for key, and one script leaf per contract. Branches: key, then leaf or leaf/path.")
    (input value "(input coin #:sign key-or-list #:path 'branch #:reveal secret-or-list #:sighash flags #:sequence n)"
           "One input spec. #:path picks a branch and sets nSequence/nLockTime; missing signatures or preimages become empty witness items. #:sighash: 'all 'none 'single, with 'anyonecanpay; 'default for taproot.")
    (output value "(output 'label lock amount)" "One output spec.")
    (output-of query "(output-of tx index)" "The coin at that output index.")
    (out query "(out tx 'label)" "The coin with that label.")
    (mine session "(mine n #:on chain #:to key)"
          "Mine n blocks, including the mempool in the first. Returns the list of coinbase coins. Coinbases mature after 100 blocks.")
    (spend value "(spend coin-or-inputs #:sign key #:path 'branch #:reveal s #:sighash flags #:sequence n #:locktime n #:outputs (list (output ...) ...))"
           "Build and sign a tx as an expression, for try and the REPL.")
    (add-input value "(add-input tx coin #:sign key ...)"
               "Append an input and sign only it. Other signatures survive only if their sighash leaves inputs free.")
    (try session "(try tx)" "Validate against the chain and mempool without changing state. Returns accepted or rejected.")
    (broadcast session "(broadcast tx)" "Validate and, if accepted, add to the mempool. Returns accepted or rejected.")
    (confirm session "(confirm tx)" "Broadcast, then mine one block if accepted.")
    (confirmed? query "(confirmed? tx)" "Whether tx is in a block.")
    (utxos query "(utxos #:on chain #:spendable-by key #:locked-by lock)"
           "Confirmed coins, ordered by height then outpoint. #:on may be left out with one chain.")
    (fee query "(fee tx)" "Inputs minus outputs.")
    (branches query "(branches coin)" "The coin's spend paths, each with what it needs.")
    (last-trace query "(last-trace)" "The trace of the most recent try or broadcast.")
    (explain query "(explain trace-or-id)"
             "A trace as data: each rule and opcode run in order, stacks top first; the failing rule carries its doc.")
    (snapshot session "(snapshot)" "Capture chains and the scenario log. Racket definitions are not captured.")
    (restore session "(restore snapshot)" "Return chains and the log to a snapshot.")
    (sig-of query "(sig-of tx input #:key key)" "The signature on an input.")
    (commits query "(commits sig)" "The fields a signature commits to.")
    (free-fields query "(free-fields tx)" "The catalogued edits that leave every signature valid.")
    (mutate query "(mutate tx path value)"
            "Apply an edit and report the signatures it breaks, with the fields that changed. Paths as for edit.")
    (edit value "(edit tx path value)"
          "tx with one field changed and witnesses kept. Paths: version, locktime, (input i sequence), (output ref amount), (output ref lock), (inputs append), (inputs remove i), (outputs append), (outputs remove ref).")
    (scenario-log query "(scenario-log)" "The log of chain, mine, try and broadcast events, oldest first.")
    (replay conformance "(replay (scenario-log) #:targets (hash 'mainnet (regtest)))"
            "Replay the log against a fresh regtest Core node. Each step is confirmed, disagree or unverified. Needs bitcoind on PATH.")
    (summary conformance "(summary run)" "Counts of confirmed, disagree and unverified steps.")
    (disagreements conformance "(disagreements run)" "The steps where the node and the model differ.")
    (describe query "(describe) (describe 'topic)" "This help. Topics: a form name, rules, opcodes, state, forms.")
    (reset-session! session "(reset-session!)" "Drop all chains, traces and the log.")))

(define results-doc
  '("try and broadcast return (accepted #:chain c #:tx t #:step n #:trace id) or"
    "(rejected #:chain c #:rule r #:input i <rule details> #:step n #:trace id)."
    "Use accepted?, rejected?, rejected-rule, rejected-input and (result-detail r 'need)."))

(define conventions
  '("Results are data: queries return values, they never print."
    "Coins are never picked implicitly: they come from mine or from labelled outputs."
    "Every rejection names a rule from the chain's consensus value; explain shows how it was reached."
    "Crypto is symbolic: a signature carries the fields it commits to. replay lowers to real bytes."))

(define (describe [topic #f])
  (cond
    [(not topic)
     (list (list 'purpose "Model Bitcoin chains, transactions and scripts, then replay them against real nodes.")
           (cons 'conventions conventions)
           (cons 'results results-doc)
           (cons 'forms (for/list ([g '(definition value session query conformance)])
                          (cons g (for/list ([f (in-list forms)] #:when (eq? (second f) g)) (first f)))))
           (list 'topics "(describe 'form-name) (describe 'rules) (describe 'opcodes) (describe 'state)"))]
    [(eq? topic 'forms) (map (λ (f) (list (first f) (third f))) forms)]
    [(eq? topic 'rules)
     (for/list ([r (in-list (consensus-rules bitcoin))])
       (list (rule-name r) '#:scope (rule-scope r) (rule-doc r)))]
    [(eq? topic 'opcodes)
     (for/list ([oc (in-list (sort (hash-values (consensus-opcodes bitcoin)) < #:key opcode-byte))])
       (list (opcode-name oc) '#:byte (opcode-byte oc) (opcode-doc oc)))]
    [(eq? topic 'state) (session-summary)]
    [(assq topic forms) => (λ (f) (list (first f) '#:usage (third f) '#:doc (fourth f)))]
    [(consensus-rule bitcoin topic) => (λ (r) (list (rule-name r) '#:scope (rule-scope r) (rule-doc r)))]
    [else (list 'unknown-topic topic "Try (describe) for the list of forms and topics.")]))
