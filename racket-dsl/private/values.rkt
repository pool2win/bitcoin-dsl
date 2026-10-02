#lang racket/base
;; Core model values: keys, symbolic hashes and signatures, locks, coins
;; and transactions.
;;
;; Crypto is symbolic. A key is a name, (hash160 k) is a structured value,
;; and a signature carries the exact list of fields it commits to, so
;; verification recomputes that list and compares.

(require racket/list
         file/sha1
         "amount.rkt")

(provide (struct-out key)
         (struct-out hashed)
         hash160
         (struct-out sig)
         (struct-out lock)
         wpkh
         lock->spk
         lock-spend-version
         lock-spendable-by?
         (struct-out outpoint)
         (struct-out coin)
         (struct-out txin)
         txin-outpoint
         (struct-out coinbase-in)
         (struct-out txout)
         (struct-out tx)
         make-tx
         tx-coinbase?
         output
         output-of
         out
         (struct-out input-spec)
         input)

;; Keys and symbolic crypto

(struct key (name)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc k port mode) (write (key-name k) port))])

(struct hashed (fn value)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc h port mode)
     (fprintf port "(~a ~s)" (hashed-fn h) (hashed-value h)))])

(define (hash160 v) (hashed 'hash160 v))

;; type is the sighash flag list, e.g. '(all); fields is the commitment,
;; an association list of (field-name . value) chosen by the consensus
;; value's sighash selector for this spend version.
(struct sig (key type fields)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc s port mode)
     (fprintf port "(sig ~s ~s)" (sig-key s) (sig-type s)))])

;; Locks (output templates)

;; A lock is how the DSL describes an output: its kind and the arguments
;; it was built from. lock->spk derives what consensus actually sees.
(struct lock (kind params)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc l port mode)
     (fprintf port "(~a~a)" (lock-kind l)
              (apply string-append
                     (for/list ([p (in-list (lock-params l))]) (format " ~s" p)))))])

(define (wpkh k)
  (unless (key? k) (raise-argument-error 'wpkh "key?" k))
  (lock 'wpkh (list k)))

(define (lock->spk l)
  (case (lock-kind l)
    [(wpkh) (list 'v0 (hash160 (first (lock-params l))))]
    [else (raise-arguments-error 'lock->spk "unknown lock kind" "lock" l)]))

(define (lock-spend-version l)
  (case (lock-kind l)
    [(wpkh) 'v0]
    [else (raise-arguments-error 'lock-spend-version "unknown lock kind" "lock" l)]))

(define (lock-spendable-by? l k)
  (and (eq? (lock-kind l) 'wpkh)
       (equal? (first (lock-params l)) k)))

;; Coins and transactions

(struct outpoint (txid vout)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc o port mode)
     (fprintf port "~a:~a" (short-txid (outpoint-txid o)) (outpoint-vout o)))])

(define (short-txid txid) (substring txid 0 8))

(struct coin (chain outpoint lock amount label)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc c port mode)
     (fprintf port "#<coin~a ~s ~s ~s>"
              (if (coin-label c) (format " ~a" (coin-label c)) "")
              (coin-outpoint c) (coin-lock c) (coin-amount c)))])

(struct txin (coin sequence witness) #:transparent)

(define (txin-outpoint in) (coin-outpoint (txin-coin in)))

;; The single input of a coinbase. The height makes each coinbase txid
;; unique, as BIP34 does.
(struct coinbase-in (height) #:transparent)

;; label is DSL metadata. It never reaches the txid or a sighash.
(struct txout (label lock amount) #:transparent)

(struct tx (chain name version locktime inputs outputs txid)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc t port mode)
     (fprintf port "#<tx~a ~a>"
              (if (tx-name t) (format " ~a" (tx-name t)) "")
              (short-txid (tx-txid t))))])

(define (make-tx chain name version locktime inputs outputs)
  (tx chain name version locktime inputs outputs
      (compute-txid version locktime inputs outputs)))

;; The txid covers exactly what a real txid covers: no witnesses, no labels.
(define (compute-txid version locktime inputs outputs)
  (define body
    (list version
          (for/list ([in (in-list inputs)])
            (if (coinbase-in? in)
                (list 'coinbase (coinbase-in-height in))
                (let ([op (txin-outpoint in)])
                  (list (outpoint-txid op) (outpoint-vout op) (txin-sequence in)))))
          (for/list ([o (in-list outputs)])
            (list (amount-sats (txout-amount o)) (lock->spk (txout-lock o))))
          locktime))
  (bytes->hex-string (sha256-bytes (string->bytes/utf-8 (format "~s" body)))))

(define (tx-coinbase? t)
  (and (pair? (tx-inputs t)) (coinbase-in? (first (tx-inputs t)))))

;; Output constructors and lookups

(define (output label l amt)
  (unless (or (not label) (symbol? label)) (raise-argument-error 'output "(or/c #f symbol?)" label))
  (unless (lock? l) (raise-argument-error 'output "lock?" l))
  (unless (amount? amt) (raise-argument-error 'output "amount?" amt))
  (txout label l amt))

(define (output-of t i)
  (define outs (tx-outputs t))
  (unless (< -1 i (length outs))
    (raise-arguments-error 'output-of "no such output" "tx" t "index" i))
  (define o (list-ref outs i))
  (coin (tx-chain t) (outpoint (tx-txid t) i) (txout-lock o) (txout-amount o) (txout-label o)))

(define (out t label)
  (define i (index-where (tx-outputs t) (λ (o) (eq? (txout-label o) label))))
  (unless i (raise-arguments-error 'out "no output with this label" "tx" t "label" label))
  (output-of t i))

;; What the author asked for on one input, before the tx is built and signed.
(struct input-spec (coin key sighash sequence) #:transparent)

(define (input c #:sign [k #f] #:sighash [type '(all)] #:sequence [sequence #xffffffff])
  (unless (coin? c) (raise-argument-error 'input "coin?" c))
  (input-spec c k type sequence))
