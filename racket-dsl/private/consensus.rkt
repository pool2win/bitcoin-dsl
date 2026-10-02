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

(struct consensus (name parent rules opcodes sighash params))

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

;; Opcodes

(define (underflow name) (script-failure 'stack-underflow (list (cons 'opcode name))))

(define (op-dup s ctx)
  (if (null? s) (underflow 'dup) (cons (car s) s)))

(define (op-hash160 s ctx)
  (if (null? s) (underflow 'hash160) (cons (hash160 (car s)) (cdr s))))

(define (op-equal s ctx)
  (if (< (length s) 2) (underflow 'equal) (cons (equal? (car s) (cadr s)) (cddr s))))

(define (op-verify s ctx)
  (cond [(null? s) (underflow 'verify)]
        [(stack-true? (car s)) (cdr s)]
        [else (script-failure 'verify '())]))

(define (op-equalverify s ctx)
  (cond [(< (length s) 2) (underflow 'equalverify)]
        [(equal? (car s) (cadr s)) (cddr s)]
        [else (script-failure 'equalverify (list (cons 'top (car s)) (cons 'second (cadr s))))]))

;; Consensus pushes false for a bad signature rather than failing; the
;; reason is kept by check-sig for the final eval-false rejection.
(define (op-checksig s ctx)
  (if (< (length s) 2)
      (underflow 'checksig)
      (cons ((script-ctx-check-sig ctx) (cadr s) (car s)) (cddr s))))

(define bitcoin-opcodes
  (for/hash ([oc (in-list
                  (list (opcode 'dup #x76 "Duplicate the top item." op-dup)
                        (opcode 'hash160 #xa9 "Replace the top item with its HASH160." op-hash160)
                        (opcode 'equal #x87 "Push whether the top two items are equal." op-equal)
                        (opcode 'verify #x69 "Fail unless the top item is true." op-verify)
                        (opcode 'equalverify #x88 "Fail unless the top two items are equal." op-equalverify)
                        (opcode 'checksig #xac "Check a signature against a pubkey and the sighash." op-checksig)))])
    (values (opcode-name oc) oc)))

;; Sighash selectors

(define (unsupported-sighash version type)
  (raise-arguments-error 'sighash "sighash type not supported yet for this spend version"
                         "version" version "type" type))

;; BIP143 with SIGHASH_ALL: what a segwit v0 signature commits to.
(define (bip143-fields t idx spent-coins type)
  (unless (equal? type '(all)) (unsupported-sighash 'v0 type))
  (define in (list-ref (tx-inputs t) idx))
  (define spent (list-ref spent-coins idx))
  (define h (second (lock->spk (coin-lock spent))))
  (list (cons 'version (tx-version t))
        (cons 'prevouts (map txin-outpoint (tx-inputs t)))
        (cons 'sequences (map txin-sequence (tx-inputs t)))
        (cons 'outpoint (txin-outpoint in))
        (cons 'script-code (p2wpkh-script h))
        (cons 'amount (coin-amount spent))
        (cons 'sequence (txin-sequence in))
        (cons 'outputs (for/list ([o (in-list (tx-outputs t))])
                         (list (txout-amount o) (lock->spk (txout-lock o)))))
        (cons 'locktime (tx-locktime t))
        (cons 'sighash-type type)))

(define (p2wpkh-script h) `(dup hash160 (push ,h) equalverify checksig))

;; Witness verification

(define (verify-witness x)
  ;;* Derive the script and starting stack from the spent output's witness program.
  (define spent (utxo-coin (vctx-spent-utxo x)))
  (define spk (lock->spk (coin-lock spent)))
  (define witness (txin-witness (vctx-input x)))
  (cond
    [(not (eq? (first spk) 'v0))
     (failure 'unsupported-spend (list (cons 'spk spk)))]
    [(not (= (length witness) 2))
     (failure 'witness-program-mismatch (list (cons 'items (length witness))))]
    [else
     ;;* Run the P2WPKH script, with a signature checker bound to this input.
     (define cause (box #f))
     (define ctx (script-ctx (make-check-sig x 'v0 cause) (vctx-emit x)))
     (define result (run-script (consensus-opcodes (vctx-consensus x))
                                (p2wpkh-script (second spk))
                                (reverse witness)
                                ctx))
     ;;* Map an interpreter failure or an unclean final stack to a named rule.
     (cond
       [(script-failure? result)
        (failure (script-failure-rule result) (script-failure-details result))]
       [(not (= (length result) 1))
        (failure 'cleanstack (list (cons 'depth (length result))))]
       [(not (stack-true? (car result)))
        (failure 'eval-false (if (unbox cause) (list (cons 'cause (unbox cause))) '()))]
       [else #f])]))

(define ((make-check-sig x version cause) s pk)
  (define fields-of (hash-ref (consensus-sighash (vctx-consensus x)) version))
  (define why
    (cond [(not (sig? s)) 'not-a-signature]
          [(not (equal? (sig-key s) pk)) 'wrong-key]
          [(not (equal? (sig-fields s)
                        (fields-of (vctx-tx x) (vctx-index x) (vctx-spent-coins x) (sig-type s))))
           'commitment-mismatch]
          [else #f]))
  (when why (set-box! cause why))
  (not why))

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
