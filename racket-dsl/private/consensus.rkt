#lang racket/base
;; Consensus is a value, not an interpreter loop.
;;
;; A consensus value holds an ordered list of named rules, an opcode table,
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
         (struct-out utxo)
         validate-tx
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

(define (run-rule r x)
  (define f ((rule-check r) x))
  ((vctx-emit x) (list 'rule (rule-name r) (vctx-index x) (if f 'fail 'pass)
                       (if f (failure-details f) '())))
  (and f (list (or (failure-rule f) (rule-name r)) (vctx-index x) (failure-details f))))

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

;; A bad signature pushes false rather than failing; check-sig records why.
(define (op-checksig s ctx)
  (if (< (length s) 2)
      (underflow 'checksig)
      (cons (script-bool ((script-ctx-check-sig ctx) (cadr s) (car s))) (cddr s))))

(define (op-checksigverify s ctx)
  (cond [(< (length s) 2) (underflow 'checksigverify)]
        [((script-ctx-check-sig ctx) (cadr s) (car s)) (cddr s)]
        [else (script-failure 'checksigverify '())]))

;; CSV and CLTV leave their argument on the stack, as the NOPs they replaced.
(define ((timelock-op name hook) s ctx)
  (cond [(null? s) (underflow name)]
        [(not (exact-integer? (car s))) (script-failure name (list (cons 'not-a-number (car s))))]
        [else (or ((hook ctx) (car s)) s)]))

(define op-csv (timelock-op 'csv script-ctx-check-sequence))
(define op-cltv (timelock-op 'cltv script-ctx-check-locktime))

(define bitcoin-opcodes
  (for/hash ([oc (in-list
                  (list (opcode 'if #x63 "Run the next branch if the top item is true." #f)
                        (opcode 'notif #x64 "Run the next branch if the top item is false." #f)
                        (opcode 'else #x67 "Switch to the other branch." #f)
                        (opcode 'endif #x68 "End a conditional." #f)
                        (opcode 'verify #x69 "Fail unless the top item is true." op-verify)
                        (opcode 'drop #x75 "Remove the top item." op-drop)
                        (opcode 'dup #x76 "Duplicate the top item." op-dup)
                        (opcode 'swap #x7c "Swap the top two items." op-swap)
                        (opcode 'size #x82 "Push the size of the top item, keeping it." op-size)
                        (opcode 'equal #x87 "Push whether the top two items are equal." op-equal)
                        (opcode 'equalverify #x88 "Fail unless the top two items are equal." op-equalverify)
                        (opcode 'add #x93 "Replace the top two numbers with their sum." op-add)
                        (opcode 'sha256 #xa8 "Replace the top item with its SHA256." op-sha256)
                        (opcode 'hash160 #xa9 "Replace the top item with its HASH160." op-hash160)
                        (opcode 'checksig #xac "Check a signature against a pubkey and the sighash." op-checksig)
                        (opcode 'checksigverify #xad "CHECKSIG, then fail unless it succeeded." op-checksigverify)
                        (opcode 'cltv #xb1 "BIP65: fail unless nLockTime has reached the top item." op-cltv)
                        (opcode 'csv #xb2 "BIP112: fail unless this input's nSequence encodes at least the top item."
                                op-csv)))])
    (values (opcode-name oc) oc)))

;; Script hooks

(define ((make-check-sig x version cause) s pk)
  (define fields-of (hash-ref (consensus-sighash (vctx-consensus x)) version))
  (define why
    (cond [(equal? s #"") 'empty-signature]
          [(not (sig? s)) 'not-a-signature]
          [(not (equal? (sig-key s) pk)) 'wrong-key]
          [(not (equal? (sig-fields s)
                        (fields-of (vctx-tx x) (vctx-index x) (vctx-spent-coins x) (sig-type s))))
           'commitment-mismatch]
          [else #f]))
  (when why (set-box! cause why))
  (not why))

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
;; A selector maps (tx, input index, spent coins, sighash type) to the
;; commitment: an alist from field name to value, in digest order. Field
;; names are relative to the signing input (own-input, own-output) because
;; that is what the digest binds, not the input's position.

;; BIP143: what a segwit v0 signature commits to. SINGLE with no output at
;; the input's index commits to no outputs (unlike legacy's "sign 1").
(define (bip143-fields t idx spent-coins type)
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

;; Witness verification

(define (verify-witness x)
  ;;* Read the witness program: a 20-byte HASH160 program is P2WPKH, a 32-byte SHA256 one is P2WSH.
  (define spk (lock->spk (coin-lock (utxo-coin (vctx-spent-utxo x)))))
  (define program (second spk))
  (define witness (txin-witness (vctx-input x)))
  (define (mismatch why) (failure 'witness-program-mismatch (list (cons 'reason why))))
  (cond
    [(not (eq? (first spk) 'v0))
     (failure 'unsupported-spend (list (cons 'spk spk)))]
    [(eq? (hashed-fn program) 'hash160)
     (if (= (length witness) 2)
         (run-witness-script x (p2wpkh-script program) (reverse witness))
         (mismatch 'p2wpkh-needs-two-items))]
    ;;* For P2WSH the last witness item is the script, and it must hash to the program.
    [(null? witness) (mismatch 'empty-witness)]
    [(not (equal? (sha256-of (last witness)) program)) (mismatch 'script-hash)]
    [else (run-witness-script x (last witness) (reverse (drop-right witness 1)))]))

(define (run-witness-script x script stack)
  ;;* Run the script with signature and timelock checks bound to this input.
  (define cause (box #f))
  (define ctx (script-ctx (make-check-sig x 'v0 cause)
                          (make-check-sequence x)
                          (make-check-locktime x)
                          (vctx-emit x)))
  (define result (run-script (consensus-opcodes (vctx-consensus x)) script stack ctx))
  (define (with-cause details)
    (if (unbox cause) (append details (list (cons 'cause (unbox cause)))) details))
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
   (rule 'value-balance 'tx "Inputs add up to at least the outputs; the difference is the fee."
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
             (hash 'v0 bip143-fields)
             (hash 'coinbase-maturity 100
                   'halving-interval 150
                   'initial-subsidy (btc 50)
                   'block-spacing 600
                   'genesis-time 1296688602)))
