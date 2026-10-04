#lang racket/base
;; Consensus is a value, not an interpreter loop.
;;
;; A consensus value holds an ordered list of named rules, an opcode table
;; keyed by byte,
;; a sighash selector per spend version, and numeric parameters. Validation
;; walks the rules in order and reports every rule run to a trace hook, so
;; a rejection always names the rule that failed and the trace shows how
;; it got there. Later rule sets extend this one by replacing or adding
;; entries (see #:extends in the design docs).

(require racket/list
         "amount.rkt"
         "crypto.rkt"
         "values.rkt"
         "script.rkt")

(provide (struct-out rule)
         (struct-out failure)
         fail
         (struct-out consensus)
         consensus-param
         consensus-rule
         consensus-opcode-named
         (struct-out utxo)
         validate-tx
         field-diff
         failure-doc
         script-failure-docs
         block-subsidy
         bitcoin)

;; scope is 'tx (checked once) or 'input (checked for each input).
;; check : vctx -> (or/c #f failure); #f means the rule passed.
(struct rule (name scope doc check))

;; rule is #f when the failure belongs to the rule that ran, or names a
;; more specific rule (an opcode, cleanstack) found while running it.
(struct failure (rule details) #:transparent)

(define (fail . kvs)
  (failure #f (let loop ([kvs kvs])
                (if (null? kvs) '() (cons (cons (car kvs) (cadr kvs)) (loop (cddr kvs)))))))

(struct consensus (name parent rules opcodes sighash params)
  #:methods gen:custom-write
  [(define (write-proc c port mode) (fprintf port "#<consensus ~a>" (consensus-name c)))])

(define (consensus-param c name) (hash-ref (consensus-params c) name))

(define (consensus-rule c name)
  (findf (λ (r) (eq? (rule-name r) name)) (consensus-rules c)))

;; The opcode this consensus runs for a name's byte, e.g. nop4 for ctv on
;; bitcoin.
(define (consensus-opcode-named c name)
  (define b (opcode-byte-of name))
  (and b (hash-ref (consensus-opcodes c) b #f)))

;; Field names whose values differ between two commitments (alists),
;; including fields present in only one.
(define (field-diff a b)
  (for/list ([k (in-list (remove-duplicates (append (map car a) (map car b))))]
             #:unless (equal? (assoc k a) (assoc k b)))
    k))

;; An entry in a chain's UTXO set.
(struct utxo (coin height coinbase?) #:transparent)

;; What a rule sees: the tx, the UTXO view it spends from, the height of
;; the block it would be in, the input index for 'input rules, and the
;; trace hook.
(struct vctx (consensus tx view height index emit))

(define (vctx-input x) (list-ref (tx-inputs (vctx-tx x)) (vctx-index x)))

(define (vctx-spent-utxo x) (hash-ref (vctx-view x) (txin-outpoint (vctx-input x))))

(define (vctx-spent-coins x)
  (for/list ([in (in-list (tx-inputs (vctx-tx x)))])
    (utxo-coin (hash-ref (vctx-view x) (txin-outpoint in)))))

;; Returns #f if t is valid, else (list rule-name input-index details).
(define (validate-tx c t view height emit)
  (define n (length (tx-inputs t)))
  (for*/first ([r (in-list (consensus-rules c))]
               [i (if (eq? (rule-scope r) 'input) (in-range n) (in-value #f))]
               [verdict (in-value (run-rule r (vctx c t view height i emit)))]
               #:when verdict)
    verdict))

;; The trace event is (rule name input outcome details failed-as), where
;; failed-as is the more specific rule a failure names (e.g. eval-false
;; inside witness-script), or #f.
(define (run-rule r x)
  (define f ((rule-check r) x))
  ((vctx-emit x) (list 'rule (rule-name r) (vctx-index x) (if f 'fail 'pass)
                       (if f (failure-details f) '())
                       (and f (failure-rule f))))
  (and f (list (or (failure-rule f) (rule-name r)) (vctx-index x) (failure-details f))))

;; Rules a failure can name from inside witness-script, besides opcodes.
(define script-failure-docs
  (hash 'eval-false "The script stopped with false on top of the stack, for example after a CHECKSIG with a signature that is not valid. #:cause gives the cause."
        'cleanstack "A segwit script must stop with exactly one item on the stack."
        'witness-program-mismatch "The witness does not agree with the witness program of the output: the number of items is wrong, or the hash of the script is not the program."
        'taproot-commitment "The control block and the leaf script do not commit to the taproot output key."
        'key-path-sig "A taproot spend through the key path must have a valid signature by the internal key. #:cause gives the cause."
        'stack-underflow "An opcode needed more stack items than the stack had."
        'bad-opcode "The script uses an opcode that this consensus does not define."
        'unbalanced-conditional "The IF, ELSE and ENDIF opcodes do not match."
        'unsupported "The model does not have this feature yet, for example locks based on time."
        'unsupported-spend "The model does not have this type of output yet."))

;; The doc for a rule name: a consensus rule, a script failure, an opcode,
;; or a failure an opcode reports (e.g. ctv-template-mismatch).
(define (failure-doc c name)
  (cond [(consensus-rule c name) => rule-doc]
        [(hash-ref script-failure-docs name #f)]
        [(consensus-opcode-named c name) => opcode-doc]
        [(for/first ([oc (in-hash-values (consensus-opcodes c))]
                     #:when (hash-ref (opcode-failures oc) name #f))
           (hash-ref (opcode-failures oc) name))]
        [else #f]))

(define (block-subsidy c height)
  (define halvings (quotient height (consensus-param c 'halving-interval)))
  (if (>= halvings 64)
      0
      (arithmetic-shift (amount-sats (consensus-param c 'initial-subsidy)) (- halvings))))

;; Timelock encodings (BIP65, BIP68, BIP112)

(define locktime-threshold 500000000)
(define sequence-final #xffffffff)
(define (sequence-disabled? n) (bitwise-bit-set? n 31))
(define (sequence-time-based? n) (bitwise-bit-set? n 22))
(define (sequence-value n) (bitwise-and n #xffff))

;; Opcodes

(define (underflow name) (script-failure 'stack-underflow (list (cons 'opcode name))))

(define (script-number v)
  (cond [(exact-integer? v) v]
        [(equal? v #"") 0]
        [else #f]))

(define ((unary name f) s ctx)
  (if (null? s) (underflow name) (f (car s) (cdr s))))

(define ((binary name f) s ctx)
  (if (< (length s) 2) (underflow name) (f (car s) (cadr s) (cddr s))))

(define op-dup (unary 'dup (λ (a rest) (list* a a rest))))
(define op-drop (unary 'drop (λ (a rest) rest)))
(define op-swap (binary 'swap (λ (a b rest) (list* b a rest))))
(define op-hash160 (unary 'hash160 (λ (a rest) (cons (hash160 a) rest))))
(define op-sha256 (unary 'sha256 (λ (a rest) (cons (sha256-of a) rest))))
(define op-equal (binary 'equal (λ (a b rest) (cons (script-bool (equal? a b)) rest))))

(define op-verify
  (unary 'verify (λ (a rest) (if (stack-true? a) rest (script-failure 'verify '())))))

(define op-equalverify
  (binary 'equalverify
          (λ (a b rest)
            (if (equal? a b)
                rest
                (script-failure 'equalverify (list (cons 'top a) (cons 'second b)))))))

;; Symbolic values have the sizes their real encodings would have.
(define (value-size v)
  (cond [(bytes? v) (bytes-length v)]
        [(secret? v) 32]
        [(key? v) 33]
        [(hashed? v) (if (eq? (hashed-fn v) 'hash160) 20 32)]
        [else #f]))

(define op-size
  (unary 'size (λ (a rest)
                 (define n (value-size a))
                 (if n (list* n a rest) (script-failure 'size (list (cons 'unsupported a)))))))

(define op-add
  (binary 'add (λ (a b rest)
                 (define x (script-number a))
                 (define y (script-number b))
                 (if (and x y)
                     (cons (+ x y) rest)
                     (script-failure 'add (list (cons 'not-a-number (if x b a))))))))

;; A bad signature pushes false rather than failing, except a non-empty
;; one in tapscript, for which check-sig returns a failure. check-sig
;; records why a signature was bad.
(define (op-checksig s ctx)
  (cond [(< (length s) 2) (underflow 'checksig)]
        [else
         (define ok ((script-ctx-check-sig ctx) (cadr s) (car s)))
         (if (script-failure? ok) ok (cons (script-bool ok) (cddr s)))]))

(define (op-checksigverify s ctx)
  (cond [(< (length s) 2) (underflow 'checksigverify)]
        [else
         (define ok ((script-ctx-check-sig ctx) (cadr s) (car s)))
         (cond [(script-failure? ok) ok]
               [ok (cddr s)]
               [else (script-failure 'checksigverify '())])]))

;; CSV and CLTV leave their argument on the stack, as the NOPs they replaced.
(define ((timelock-op name hook) s ctx)
  (cond [(null? s) (underflow name)]
        [(not (exact-integer? (car s))) (script-failure name (list (cons 'not-a-number (car s))))]
        [else (or ((hook ctx) (car s)) s)]))

(define op-csv (timelock-op 'csv script-ctx-check-sequence))
(define op-cltv (timelock-op 'cltv script-ctx-check-locktime))

(define (op-nop s ctx) s)

(define bitcoin-opcodes
  (for/hash ([oc (in-list
                  (list (make-opcode 'if #x63 "Run the next branch if the top item is true." #f #:kind 'flow)
                        (make-opcode 'notif #x64 "Run the next branch if the top item is false." #f #:kind 'flow)
                        (make-opcode 'else #x67 "Switch to the other branch." #f #:kind 'flow)
                        (make-opcode 'endif #x68 "End a conditional." #f #:kind 'flow)
                        (make-opcode 'verify #x69 "Fail unless the top item is true." op-verify)
                        (make-opcode 'drop #x75 "Remove the top item." op-drop)
                        (make-opcode 'dup #x76 "Duplicate the top item." op-dup)
                        (make-opcode 'swap #x7c "Swap the top two items." op-swap)
                        (make-opcode 'size #x82 "Push the size of the top item. The item stays on the stack." op-size)
                        (make-opcode 'equal #x87 "Push true if the top two items are equal, else push false." op-equal)
                        (make-opcode 'equalverify #x88 "Fail unless the top two items are equal." op-equalverify)
                        (make-opcode 'add #x93 "Replace the top two numbers with their sum." op-add)
                        (make-opcode 'sha256 #xa8 "Replace the top item with its SHA256." op-sha256)
                        (make-opcode 'hash160 #xa9 "Replace the top item with its HASH160." op-hash160)
                        (make-opcode 'checksig #xac "Check a signature against a pubkey and the sighash." op-checksig)
                        (make-opcode 'checksigverify #xad "CHECKSIG, then fail unless it succeeded." op-checksigverify)
                        (make-opcode 'nop1 #xb0 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)
                        (make-opcode 'cltv #xb1 "BIP65: fail unless nLockTime has reached the top item." op-cltv)
                        (make-opcode 'csv #xb2 "BIP112: fail unless this input's nSequence encodes at least the top item."
                                     op-csv)
                        (make-opcode 'nop4 #xb3 "Does nothing; reserved for soft-fork upgrades (BIP119 proposes CTV)." op-nop #:kind 'nop)
                        (make-opcode 'nop5 #xb4 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)
                        (make-opcode 'nop6 #xb5 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)
                        (make-opcode 'nop7 #xb6 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)
                        (make-opcode 'nop8 #xb7 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)
                        (make-opcode 'nop9 #xb8 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)
                        (make-opcode 'nop10 #xb9 "Does nothing; reserved for soft-fork upgrades." op-nop #:kind 'nop)))])
    (values (opcode-byte oc) oc)))

;; Script hooks

;; leaf is the tapleaf hash for a tapscript spend, else #f. strict? makes a
;; non-empty bad signature fail the script (BIP342).
;; cause is a box that receives the details of the last bad signature,
;; e.g. ((cause . commitment-mismatch) (fields (outputs all))).
(define ((make-check-sig x version leaf cause strict?) s pk)
  (define problem (sig-problem x version leaf s pk))
  (when problem (set-box! cause problem))
  (cond [(not problem) #t]
        [(and strict? (not (eq? (cdar problem) 'empty-signature)))
         (script-failure 'checksig problem)]
        [else #f]))

;; Why s is not a valid signature by pk for input x, as rejection details,
;; or #f if it is valid. A commitment mismatch lists the fields that differ.
(define (sig-problem x version leaf s pk)
  (define fields-of (hash-ref (consensus-sighash (vctx-consensus x)) version))
  (define (because why) (list (cons 'cause why)))
  (cond [(equal? s #"") (because 'empty-signature)]
        [(not (sig? s)) (because 'not-a-signature)]
        [(not (equal? (sig-key s) pk)) (because 'wrong-key)]
        [else
         (define now (fields-of (vctx-tx x) (vctx-index x) (vctx-spent-coins x) (sig-type s) leaf))
         (cond [(assq 'invalid now) => (λ (p) (because (cdr p)))]
               [(not (equal? (sig-fields s) now))
                (list (cons 'cause 'commitment-mismatch)
                      (cons 'fields (for/list ([f (in-list (sig-fields s))]
                                               #:unless (equal? f (assoc (car f) now)))
                                      (car f))))]
               [else #f])]))

(define ((make-check-sequence x) n)
  (define seq (txin-sequence (vctx-input x)))
  (define (no why) (script-failure 'csv (list (cons 'need n) (cons 'sequence seq) (cons 'reason why))))
  (cond [(negative? n) (no 'negative)]
        [(sequence-disabled? n) #f]
        [(< (tx-version (vctx-tx x)) 2) (no 'tx-version-below-2)]
        [(sequence-disabled? seq) (no 'sequence-disabled)]
        [(not (eq? (sequence-time-based? n) (sequence-time-based? seq))) (no 'lock-type-mismatch)]
        [(> (sequence-value n) (sequence-value seq)) (no 'sequence-too-low)]
        [else #f]))

(define ((make-check-locktime x) n)
  (define lt (tx-locktime (vctx-tx x)))
  (define (no why) (script-failure 'cltv (list (cons 'need n) (cons 'locktime lt) (cons 'reason why))))
  (cond [(negative? n) (no 'negative)]
        [(not (eq? (< n locktime-threshold) (< lt locktime-threshold))) (no 'lock-type-mismatch)]
        [(> n lt) (no 'locktime-too-low)]
        [(= (txin-sequence (vctx-input x)) sequence-final) (no 'input-final)]
        [else #f]))

;; Sighash selectors
;;
;; A selector maps (tx, input index, spent coins, sighash type, leaf) to
;; the commitment: an alist from field name to value. leaf is the tapleaf
;; hash for a tapscript spend, else #f. Field names are relative to the
;; signing input (own-input, own-output) because that is what the digest
;; binds. A commitment containing (invalid . reason) can never verify.

;; BIP143: what a segwit v0 signature commits to. SINGLE with no output at
;; the input's index commits to no outputs (unlike legacy's "sign 1").
(define (bip143-fields t idx spent-coins type leaf)
  (when (equal? type '(default))
    (raise-arguments-error 'sighash "default is a taproot sighash type" "type" type))
  (define base (car type))
  (define acp? (memq 'anyonecanpay type))
  (define ins (tx-inputs t))
  (define outs (tx-outputs t))
  (define in (list-ref ins idx))
  (define spent (list-ref spent-coins idx))
  (define (output-value o) (list (txout-amount o) (lock->spk (txout-lock o))))
  (append
   (list (cons 'version (tx-version t)))
   (if acp? '() (list (cons '(inputs outpoints) (map txin-outpoint ins))))
   (if (or acp? (not (eq? base 'all))) '() (list (cons '(inputs sequences) (map txin-sequence ins))))
   (list (cons '(own-input outpoint) (txin-outpoint in))
         (cons '(own-prevout script) (lock-script-code (coin-lock spent)))
         (cons '(own-prevout amount) (coin-amount spent))
         (cons '(own-input sequence) (txin-sequence in)))
   (case base
     [(all) (list (cons '(outputs all) (map output-value outs)))]
     [(single) (if (< idx (length outs))
                   (list (cons '(own-output) (output-value (list-ref outs idx))))
                   '())]
     [(none) '()])
   (list (cons 'locktime (tx-locktime t))
         (cons 'sighash-type type))))

;; BIP341: what a taproot signature commits to. Unlike BIP143 it commits to
;; every input's amount and scriptPubKey, to all sequences whenever not
;; ANYONECANPAY, and to the input's index rather than its outpoint.
(define (bip341-fields t idx spent-coins type leaf)
  (define base (car type))
  (define acp? (memq 'anyonecanpay type))
  (define ins (tx-inputs t))
  (define outs (tx-outputs t))
  (define in (list-ref ins idx))
  (define spent (list-ref spent-coins idx))
  (define (output-value o) (list (txout-amount o) (lock->spk (txout-lock o))))
  (if (and (eq? base 'single) (>= idx (length outs)))
      (list (cons 'invalid 'single-without-output) (cons 'sighash-type type))
      (append
       (list (cons 'version (tx-version t))
             (cons 'locktime (tx-locktime t)))
       (if acp?
           '()
           (list (cons '(inputs outpoints) (map txin-outpoint ins))
                 (cons '(inputs amounts) (map coin-amount spent-coins))
                 (cons '(inputs spks) (map (λ (c) (lock->spk (coin-lock c))) spent-coins))
                 (cons '(inputs sequences) (map txin-sequence ins))))
       (if (memq base '(default all)) (list (cons '(outputs all) (map output-value outs))) '())
       (list (cons 'spend-type (if leaf 'script 'key)))
       (if acp?
           (list (cons '(own-input outpoint) (txin-outpoint in))
                 (cons '(own-prevout amount) (coin-amount spent))
                 (cons '(own-prevout spk) (lock->spk (coin-lock spent)))
                 (cons '(own-input sequence) (txin-sequence in)))
           (list (cons '(own-input index) idx)))
       (if (eq? base 'single) (list (cons '(own-output) (output-value (list-ref outs idx)))) '())
       (if leaf (list (cons '(own-leaf) leaf) (cons 'codesep-position #xffffffff)) '())
       (list (cons 'sighash-type type)))))

;; Witness verification

(define (verify-witness x)
  ;;* Read the witness program: v0 with a HASH160 program is P2WPKH, v0 with a SHA256 one is P2WSH, v1 is taproot.
  (define spk (lock->spk (coin-lock (utxo-coin (vctx-spent-utxo x)))))
  (define program (second spk))
  (define witness (txin-witness (vctx-input x)))
  (define (mismatch why) (failure 'witness-program-mismatch (list (cons 'reason why))))
  (case (first spk)
    [(v0)
     (cond
       [(eq? (hashed-fn program) 'hash160)
        (if (= (length witness) 2)
            (run-witness-script x 'v0 #f (p2wpkh-script program) (reverse witness))
            (mismatch 'p2wpkh-needs-two-items))]
       ;;* For P2WSH the last witness item is the script, and it must hash to the program.
       [(null? witness) (mismatch 'empty-witness)]
       [(not (equal? (sha256-of (last witness)) program)) (mismatch 'script-hash)]
       [else (run-witness-script x 'v0 #f (last witness) (reverse (drop-right witness 1)))])]
    [(v1) (verify-taproot x program witness mismatch)]
    [else (failure 'unsupported-spend (list (cons 'spk spk)))]))

(define (verify-taproot x output-key witness mismatch)
  (define internal (first (hashed-value output-key)))
  (cond
    [(null? witness) (mismatch 'empty-witness)]
    ;;* Key path: the single item is a signature by the internal key, with the output key's tweak implied.
    [(null? (cdr witness))
     (define cause (box #f))
     (define ok ((make-check-sig x 'v1 #f cause #t) (car witness) internal))
     (if (eq? ok #t)
         #f
         (failure 'key-path-sig (unbox cause)))]
    ;;* Script path: the leaf script and control block must commit to the output key.
    [else
     (define c (last witness))
     (define script (list-ref witness (- (length witness) 2)))
     (cond
       [(not (control? c)) (mismatch 'not-a-control-block)]
       [(not (equal? (taptweak (control-internal c) (merkle-root (tapleaf script) (control-path c)))
                     output-key))
        (failure 'taproot-commitment '())]
       [else (run-witness-script x 'v1 (tapleaf script) script (reverse (drop-right witness 2)))])]))

;; version is the sighash version; leaf is set for tapscript, which also
;; makes bad non-empty signatures fail the script.
(define (run-witness-script x version leaf script stack)
  ;;* Run the script with signature and timelock checks bound to this input.
  (define cause (box #f))
  (define ctx (script-ctx (make-check-sig x version leaf cause (and leaf #t))
                          (make-check-sequence x)
                          (make-check-locktime x)
                          (vctx-emit x)
                          (vctx-tx x)
                          (vctx-index x)
                          (vctx-spent-coins x)))
  (define result (run-script (consensus-opcodes (vctx-consensus x)) script stack ctx))
  (define (with-cause details)
    (if (and (unbox cause) (not (assq 'cause details)))
        (append details (unbox cause))
        details))
  ;;* Map an interpreter failure or an unclean final stack to a named rule, adding why a signature failed.
  (cond
    [(script-failure? result)
     (failure (script-failure-rule result)
              (if (eq? (script-failure-rule result) 'checksigverify)
                  (with-cause (script-failure-details result))
                  (script-failure-details result)))]
    [(not (= (length result) 1))
     (failure 'cleanstack (list (cons 'depth (length result))))]
    [(not (stack-true? (car result)))
     (failure 'eval-false (with-cause '()))]
    [else #f]))

;; The bitcoin rule set

(define max-money (* 21000000 sats-per-btc))

(define (output-sats x) (map (λ (o) (amount-sats (txout-amount o))) (tx-outputs (vctx-tx x))))

(define bitcoin-rules
  (list
   (rule 'inputs-nonempty 'tx "A transaction spends at least one coin."
         (λ (x) (and (null? (tx-inputs (vctx-tx x))) (fail))))
   (rule 'outputs-nonempty 'tx "A transaction creates at least one output."
         (λ (x) (and (null? (tx-outputs (vctx-tx x))) (fail))))
   (rule 'output-range 'tx "Every output amount, and their total, lies between 0 and 21M BTC."
         (λ (x)
           (define amts (output-sats x))
           (define bad (for/first ([a (in-list amts)] [j (in-naturals)]
                                   #:unless (<= 0 a max-money))
                         j))
           (cond [bad (fail 'output bad)]
                 [(> (apply + amts) max-money) (fail 'total (sats (apply + amts)))]
                 [else #f])))
   (rule 'duplicate-inputs 'tx "No coin is spent twice by one transaction."
         (λ (x)
           (define dup (check-duplicates (map txin-outpoint (tx-inputs (vctx-tx x)))))
           (and dup (fail 'outpoint dup))))
   (rule 'locktime-final 'tx
         "A transaction with nLockTime set waits until a block above that height, unless every input's nSequence is final."
         (λ (x)
           (define t (vctx-tx x))
           (define lt (tx-locktime t))
           (cond [(zero? lt) #f]
                 [(andmap (λ (in) (= (txin-sequence in) sequence-final)) (tx-inputs t)) #f]
                 [(>= lt locktime-threshold) (failure 'unsupported (list (cons 'feature 'time-based-locktime)))]
                 [(< lt (vctx-height x)) #f]
                 [else (fail 'need (add1 lt) 'have (vctx-height x))])))
   (rule 'input-exists 'input "Each input spends an unspent coin on this chain."
         (λ (x)
           (define op (txin-outpoint (vctx-input x)))
           (and (not (hash-ref (vctx-view x) op #f)) (fail 'outpoint op))))
   (rule 'coinbase-maturity 'input "A coinbase output is spendable once it is 100 blocks deep."
         (λ (x)
           (define u (vctx-spent-utxo x))
           (define need (consensus-param (vctx-consensus x) 'coinbase-maturity))
           (define have (- (vctx-height x) (utxo-height u)))
           (and (utxo-coinbase? u) (< have need) (fail 'need need 'have have))))
   (rule 'value-balance 'tx "The sum of the inputs is equal to or more than the sum of the outputs. The difference is the fee."
         (λ (x)
           (define in (for/sum ([c (in-list (vctx-spent-coins x))]) (amount-sats (coin-amount c))))
           (define out-total (apply + (output-sats x)))
           (and (< in out-total) (fail 'in (sats in) 'out (sats out-total)))))
   (rule 'sequence-lock 'input
         "BIP68: an input whose nSequence encodes a relative lock waits that many blocks after its coin confirmed."
         (λ (x)
           (define seq (txin-sequence (vctx-input x)))
           (cond [(< (tx-version (vctx-tx x)) 2) #f]
                 [(sequence-disabled? seq) #f]
                 [(sequence-time-based? seq) (failure 'unsupported (list (cons 'feature 'time-based-sequence-lock)))]
                 [else
                  (define need (sequence-value seq))
                  (define have (- (vctx-height x) (utxo-height (vctx-spent-utxo x))))
                  (and (< have need) (fail 'need need 'have have))])))
   (rule 'witness-script 'input "Each input's witness satisfies the script of the coin it spends."
         verify-witness)))

;; Parameters follow regtest so conformance replays line up.
(define bitcoin
  (consensus 'bitcoin
             #f
             bitcoin-rules
             bitcoin-opcodes
             (hash 'v0 bip143-fields 'v1 bip341-fields)
             (hash 'coinbase-maturity 100
                   'halving-interval 150
                   'initial-subsidy (btc 50)
                   'block-spacing 600
                   'genesis-time 1296688602)))
