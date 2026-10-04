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
(define forms
  '((chain definition "(chain name #:rules consensus)"
           "Define a chain named name with a fresh genesis at height 0. Name chains mainnet, signet, etc.; btc is the amount constructor. bitcoin uses regtest parameters: 50 BTC subsidy halving every 150 blocks, coinbase maturity 100.")
    (keys definition "(keys name ...)"
          "Bind each name to a key of that name. Keys are symbolic; replay derives real keys from the names.")
    (secret value "(secret 'name)"
            "A hash preimage, used with (sha256 s) in contracts and revealed with #:reveal.")
    (contract definition "(contract name (param ...) policy)"
              "Define name as a function from params to a P2WSH lock. Policy forms: (pk k) (sha256 s) (older blocks) (after height) (ctv template) (and p ...) (or arm ...) (thresh k (pk a) ...). An or arm may be labelled [label policy]; labels name spend paths. (older n) counts the coin's own block: right after the funding block is mined, a try sees age 1, so mine n-1 more blocks.")
    (define-tx definition "(define-tx name #:inputs ([coin input-option ...] ...) #:outputs ([label lock amount] ...))"
               "Build and sign a tx, bind it to name and bind each output label to that output's coin as a top-level definition (a later define-tx with the same label rebinds it). Input options as for input, e.g. [cb #:sign alice #:sighash '(all anyonecanpay)].")
    (btc value "(btc 49.99)" "An amount in BTC, kept as exact satoshis.")
    (sats value "(sats 1000)" "An amount in satoshis.")
    (wpkh value "(wpkh key)" "A P2WPKH lock.")
    (tr value "(tr key #:leaves (list contract-lock ...))"
        "A taproot lock: key path for key, and one script leaf per contract. Branches: key, then leaf or leaf/path.")
    (input value "(input coin #:sign key-or-list #:path 'branch #:reveal secret-or-list #:sighash flags #:sequence n)"
           "One input spec. #:path picks a branch and sets nSequence/nLockTime; missing signatures or preimages become empty witness items. #:sighash is 'all, 'none or 'single, or a list adding anyonecanpay, e.g. '(all anyonecanpay); 'default for taproot.")
    (output value "(output 'label lock amount)" "One output spec.")
    (output-of query "(output-of tx index)" "The coin at that output index.")
    (out query "(out tx 'label)" "The coin with that label.")
    (mine session "(mine n #:on chain #:to key)"
          "Mine n blocks, including the mempool in the first. Returns the list of coinbase coins (wrap in void to discard). Without #:to, coinbases pay an anonymous miner no user key can spend. Coinbases mature after 100 blocks; the subsidy halves every 150 blocks.")
    (spend value "(spend coin-or-inputs #:sign key-or-list #:path 'branch #:reveal s #:sighash flags #:sequence n #:locktime n #:name 'name #:outputs (list (output 'label lock amount) ...))"
           "Build and sign a tx as an expression, for try and the REPL; labels are only reachable with out. #:path sets nSequence and nLockTime for that branch, so #:sequence and #:locktime are rarely needed. Give a list of (input ...) specs to spend several coins.")
    (add-input value "(add-input tx coin #:sign key ...)  ; returns a tx named <name>+input"
               "Append an input and sign only it. Other signatures survive only if their sighash leaves inputs free.")
    (try session "(try tx)" "Validate against the chain and mempool without changing state. Returns accepted or rejected.")
    (broadcast session "(broadcast tx)" "Validate and, if accepted, add to the mempool. Returns accepted or rejected.")
    (confirm session "(confirm tx)" "Broadcast, then mine one block (coinbase to the anonymous miner) if accepted. Spends the inputs for good; use try or snapshot first to keep alternatives open.")
    (confirmed? query "(confirmed? tx)" "Whether tx is in a block.")
    (height query "(height #:on chain)" "The chain's tip height. #:on may be left out with one chain.")
    (utxos query "(utxos #:on chain #:spendable-by key #:locked-by lock)"
           "Confirmed coins, ordered by height then outpoint. #:on may be left out with one chain.")
    (fee query "(fee tx)" "Inputs minus outputs. Negative means the outputs exceed the inputs; try rejects that with value-balance.")
    (branches query "(branches coin)" "The coin's spend paths, each with what it needs.")
    (last-trace query "(last-trace)" "The trace of the most recent try or broadcast.")
    (explain query "(explain trace-or-id)"
             "A trace as data: each rule and opcode run in order, stacks top first; the failing rule carries its doc.")
    (snapshot session "(snapshot)" "Capture chains and the scenario log. Racket definitions are not captured.")
    (restore session "(restore snapshot)" "Return chains and the log to a snapshot.")
    (sig-of query "(sig-of tx input #:key key)" "The signature on an input.")
    (commits query "(commits sig)" "The fields a signature commits to; the list depends on the spend version and flags. See (describe 'sighash) for the field names.")
    (free-fields query "(free-fields tx)" "The catalogued edits that leave every signature valid: (inputs append), (inputs remove-others), (outputs append), (output ref amount), (output ref lock), (input i sequence), version, locktime.")
    (mutate query "(mutate tx path value)"
            "Apply an edit and report the signatures it breaks, with the fields that changed. Paths as for edit.")
    (edit value "(edit tx path value)"
          "tx with one field changed and witnesses kept. Paths: version, locktime, (input i sequence), (output ref amount), (output ref lock), (inputs append) with a coin, (inputs remove i), (outputs append) with an (output ...), (outputs remove ref). ref is an output label or index; i is an input index.")
    (scenario-log query "(scenario-log)" "The log of chain, mine, try and broadcast events, oldest first.")
    (replay conformance "(replay (scenario-log) #:targets (hash 'mainnet (regtest) 'signet (regtest #:build 'inquisition)))"
            "Replay the log against fresh regtest nodes, one per chain. Each step is confirmed (the node agrees on consensus), disagree, or unverified (#:reason says why: no target, (model-only-rule ctv) when the step ran a rule the target runs differently, a dependency on an unverified step, or something lowering cannot express). #:mempool-only on a confirmed step means the node's mempool refused the tx by policy but a block would accept it. Inspect with summary, disagreements, unverified-steps, run-steps and step-n/step-status/step-detail/step-event.")
    (regtest conformance "(regtest #:build 'core|'inquisition #:bitcoind path)"
             "A replay target. core runs bitcoin (bitcoind on PATH); inquisition runs bitcoin plus CTV (the consensus value inquisition), found via BITCOIN_INQUISITION or ~/projects/bitcoin-inquisition/build/bin/bitcoind.")
    (unverified-steps conformance "(unverified-steps run)" "The steps replay could not check, each with its #:reason.")
    (run-steps conformance "(run-steps run)" "Every step of a run: (status #:step n event detail); read with step-n, step-status, step-event, step-detail.")
    (summary conformance "(summary run)" "Counts of confirmed, disagree and unverified steps.")
    (disagreements conformance "(disagreements run)" "The steps where the node and the model differ.")
    (define-consensus consensus "(define-consensus name #:extends parent #:opcodes (upgrade nop4 #:to ctv) #:rules (add r) (remove n) (replace n r) #:params (set k v) #:sighash (add version selector))"
                      "Define a consensus value as changes to a parent: e.g. a soft fork upgrading an upgradable NOP to a proposal opcode (known: ctv). Give it to chain with #:rules. Opcode names are not evaluated.")
    (diff-consensus consensus "(diff-consensus a b)"
                    "What changes from a to b: (opcode #xb3 nop4 -> ctv), (rule + name), (rule - name), (rule ~ name), (param k old -> new), (sighash + version).")
    (template consensus "(template #:outputs (list (output ...)) #:version 2 #:locktime 0 #:inputs 1 #:sequences (...) #:index 0)"
              "A CTV (BIP119) template: what a coin locked with (ctv template) must be spent by. Defaults match spend and define-tx.")
    (audit consensus "(audit lock #:on chain)"
           "Where lock's scripts would not be enforced as written on a chain, e.g. (warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4). '() when clean.")
    (sighash-search query "(sighash-search tx #:goal (can (add-input) ...) #:keep (fixed (outputs all) ...) #:over '(wpkh tr-key tr-script))"
                    "The (spend-type flags) under which tx's signers could sign so the goal edits are free and the kept fields are not. Goal words: add-input remove-inputs add-output change-outputs change-version change-locktime. Keep: (outputs all) (inputs all) (output ref) version locktime.")
    (sighash-matrix conformance "(sighash-matrix #:spend-types '(wpkh tr-key tr-script) #:flags 'all #:target (regtest))"
                    "For every spend type, flag set and edit, the model's verdict checked against a real node, in a scratch session. Rows (status #:type #:flags #:edit #:model ...).")
    (describe query "(describe) (describe 'topic)" "This help. Topics: example, a form name, a rule name, rules, opcodes, state, forms.")
    (reset-session! session "(reset-session!)" "Drop all chains, traces and the log.")))

(define results-doc
  '("try and broadcast return (accepted #:chain c #:tx t #:step n #:trace id) or"
    "(rejected #:chain c #:rule r #:input i <rule details> #:step n #:trace id)."
    "Use accepted?, rejected?, rejected-rule, rejected-input and (result-detail r 'need)."))

(define conventions
  '("Results are data: queries return values, they never print."
    "Coins are never picked implicitly: they come from mine or from labelled outputs."
    "Every rejection names a rule; (describe 'rule-name) documents it and explain shows how it was reached."
    "Crypto is symbolic: a signature carries the fields it commits to. replay lowers to real bytes."))

(define tips
  '("try tests a tx without changing state; confirm spends its inputs for good."
    "snapshot before exploring alternatives, restore to go back."
    "Mature coinbases with (void (mine 100 #:on chain)): no #:to pays an anonymous miner and keeps your keys' coins clean."
    "Mine all the coins you need early: the subsidy halves every 150 blocks."))

;; What each sighash flag commits to, and the field names commits uses.
(define sighash-doc
  '((flags "#:sighash 'all (default for segwit v0), 'none, 'single, each optionally with anyonecanpay as a list: '(all anyonecanpay). 'default is taproot's default and commits like all.")
    (segwit-v0 "BIP143. Always: version, own-input outpoint and sequence, own-prevout script and amount, locktime. Without anyonecanpay: (inputs outpoints), and with all also (inputs sequences). all: (outputs all); single: (own-output), or no outputs if there is none at the input's index; none: no outputs.")
    (taproot "BIP341. Always: version, locktime, spend-type. Without anyonecanpay: (inputs outpoints) (inputs amounts) (inputs spks) (inputs sequences) and (own-input index); with anyonecanpay: own-input outpoint and sequence, own-prevout amount and spk. all/default: (outputs all); single: (own-output), invalid if there is none; none: no outputs. Script path adds (own-leaf) and codesep-position.")
    (fields "own-* names are relative to the signing input; (inputs ...) and (outputs all) cover every input or output, so adding or removing one changes them.")
    (queries "commits lists a signature's fields; free-fields lists edits no signature commits to; mutate applies an edit and reports which signatures break on which fields; a commitment-mismatch rejection carries the same #:fields.")))

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
     (list (list 'purpose "Model Bitcoin chains, transactions and scripts, then replay them against real nodes.")
           (cons 'conventions conventions)
           (cons 'results results-doc)
           (cons 'tips tips)
           (cons 'example example)
           (cons 'forms (for/list ([g '(definition value consensus session query conformance)])
                          (cons g (for/list ([f (in-list forms)] #:when (eq? (second f) g)) (third f)))))
           (list 'topics "describe a form, rule or opcode name, a group name (definition value consensus session query conformance), or a consensus name (e.g. bitcoin); also rules, opcodes, sighash, state, example")
           (list 'consensus-values (registered-consensus-names)
                 "bound in eval: bitcoin, inquisition (with bitcoin/conform), and those you define"))]
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
                  "witness-script failures name a more specific rule: one of these, or the opcode that failed (see opcodes)."))
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
                      "describe rules or opcodes with this consensus value as the second argument for details."))]
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
