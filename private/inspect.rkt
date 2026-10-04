#lang racket/base
;; Sighash queries: what each signature commits to, and which edits to a
;; signed tx leave every signature valid.
;;
;; mutate and free-fields never reason about flags directly. They edit the
;; tx and recompute each existing signature's commitment with the same
;; consensus selector verification uses, so they cannot disagree with it.

(require racket/list
         racket/match
         "amount.rkt"
         "crypto.rkt"
         "values.rkt"
         "policy.rkt"
         "consensus.rkt"
         "compose.rkt"
         "session.rkt")

(provide sig-of
         commits
         edit
         mutate
         (struct-out breaks)
         intact?
         free-fields
         audit
         can
         fixed
         sighash-search
         flag-sets)

;; Signatures

;; The signature in input i's witness; #:key picks one when there are several.
(define (sig-of t i #:key [k #f])
  (define sigs (filter (λ (x) (and (sig? x) (or (not k) (equal? (sig-key x) k))))
                       (txin-witness (list-ref (tx-inputs t) i))))
  (when (null? sigs) (raise-arguments-error 'sig-of "no signature on this input" "tx" t "input" i))
  (first sigs))

;; The fields a signature commits to, in digest order.
(define (commits s)
  (for/list ([f (in-list (sig-fields s))] #:unless (eq? (car f) 'sighash-type))
    (car f)))

;; Edits

;; Returns t with one field changed. Witnesses are kept as they are, so
;; signatures can be checked against the edited tx. Paths:
;;   version, locktime                      value: number
;;   (input i sequence)                     value: number
;;   (output ref amount), (output ref lock) ref: label or index
;;   (inputs append)                        value: coin
;;   (inputs remove i)
;;   (outputs append)                       value: (output ...)
;;   (outputs remove ref)
(define (edit t path [value #f])
  (define ins (tx-inputs t))
  (define outs (tx-outputs t))
  (define (rebuild #:version [v (tx-version t)] #:locktime [lt (tx-locktime t)]
                   #:inputs [is ins] #:outputs [os outs])
    (make-tx (tx-chain t) (tx-name t) v lt is os))
  (match path
    ['version (rebuild #:version value)]
    ['locktime (rebuild #:locktime value)]
    [(list 'input i 'sequence)
     (rebuild #:inputs (list-update ins i (λ (in) (struct-copy txin in [sequence value]))))]
    [(list 'output ref 'amount)
     (rebuild #:outputs (list-update outs (output-index t ref) (λ (o) (struct-copy txout o [amount value]))))]
    [(list 'output ref 'lock)
     (rebuild #:outputs (list-update outs (output-index t ref) (λ (o) (struct-copy txout o [lock value]))))]
    [(list 'inputs 'append) (rebuild #:inputs (append ins (list (txin value #xffffffff '()))))]
    [(list 'inputs 'remove i) (rebuild #:inputs (remove-at ins i))]
    [(list 'outputs 'append) (rebuild #:outputs (append outs (list value)))]
    [(list 'outputs 'remove ref) (rebuild #:outputs (remove-at outs (output-index t ref)))]
    [_ (raise-arguments-error 'edit "unknown edit path" "path" path)]))

(define (remove-at xs i) (append (take xs i) (drop xs (add1 i))))

(define (output-index t ref)
  (cond
    [(exact-nonnegative-integer? ref) ref]
    [(index-where (tx-outputs t) (λ (o) (eq? (txout-label o) ref))) => values]
    [else (raise-arguments-error 'edit "no output with this label" "tx" t "label" ref)]))

;; Breakage

;; entries: one (sig key input #:fields (field ...)) per broken signature,
;; where input is its index in the tx before the edit.
(struct breaks (entries)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc b port mode) (fprintf port "(breaks ~s)" (breaks-entries b)))])

(define (intact? b) (null? (breaks-entries b)))

;; Every signature in t that is no longer valid in edited. A signature
;; whose input was removed is gone rather than broken.
(define (sig-breaks t edited)
  (define selectors (consensus-sighash (chain-consensus (tx-chain t))))
  (define spent (map txin-coin (tx-inputs edited)))
  (breaks
   (for*/list ([(in i) (in-parallel (tx-inputs t) (in-naturals))]
               [s (in-list (txin-witness in))]
               #:when (sig? s)
               [j (in-value (index-where (tx-inputs edited)
                                         (λ (x) (equal? (txin-outpoint x) (txin-outpoint in)))))]
               #:when j
               [select (in-value (hash-ref selectors (lock-spend-version (coin-lock (txin-coin in)))))]
               [leaf (in-value (witness-leaf (txin-witness (list-ref (tx-inputs edited) j))))]
               [diff (in-value (field-diff (sig-fields s) (select edited j spent (sig-type s) leaf)))]
               #:unless (null? diff))
     (list 'sig (sig-key s) i '#:fields diff))))

(define (mutate t path [value #f]) (sig-breaks t (edit t path value)))

;; Free fields

;; Its name cannot be written with keys, so it never collides with a user key.
(define nobody (key '|probe key|))

;; A coin no real chain has, used to probe whether inputs can be added.
(define (probe-coin t)
  (coin (tx-chain t) (outpoint (make-string 64 #\0) 0) (wpkh nobody) (sats 1) #f))

(define (nudge-amount a) (sats (if (positive? (amount-sats a)) (sub1 (amount-sats a)) 1)))

;; The edits, from a fixed catalogue, that leave every signature in t
;; valid. Outputs are named by label when they have one.
;;   (inputs append)        another input can be added
;;   (inputs remove-others) each signed input survives alone, and the
;;                          input set is not committed (else a one-input
;;                          tx would pass vacuously)
;;   (outputs append)       another output can be added
;;   (output ref amount), (output ref lock), (input i sequence), version, locktime
(define (free-fields t)
  (define (ref j) (or (txout-label (list-ref (tx-outputs t) j)) j))
  (define (survives? path value) (intact? (mutate t path value)))
  (define candidates
    (append
     (list (cons '(inputs append) (λ () (survives? '(inputs append) (probe-coin t))))
           (cons '(inputs remove-others) (λ () (and (survives? '(inputs append) (probe-coin t))
                                                    (survives-alone? t))))
           (cons '(outputs append) (λ () (survives? '(outputs append) (output #f (wpkh nobody) (sats 1))))))
     (append*
      (for/list ([o (in-list (tx-outputs t))] [j (in-naturals)])
        (list (cons `(output ,(ref j) amount) (λ () (survives? `(output ,j amount) (nudge-amount (txout-amount o)))))
              (cons `(output ,(ref j) lock) (λ () (survives? `(output ,j lock) (wpkh nobody)))))))
     (for/list ([in (in-list (tx-inputs t))] [i (in-naturals)])
       (cons `(input ,i sequence)
             (λ () (survives? `(input ,i sequence) (bitwise-xor (txin-sequence in) 1)))))
     (list (cons 'version (λ () (survives? 'version (if (= (tx-version t) 2) 1 2))))
           (cons 'locktime (λ () (survives? 'locktime (bitwise-xor (tx-locktime t) 1)))))))
  (for/list ([c (in-list candidates)] #:when ((cdr c))) (car c)))

(define (survives-alone? t)
  (for/and ([in (in-list (tx-inputs t))]
            #:when (ormap sig? (txin-witness in)))
    (intact? (sig-breaks t (make-tx (tx-chain t) (tx-name t) (tx-version t) (tx-locktime t)
                                    (list in) (tx-outputs t))))))

;; Audit

;; Where lock's scripts would not be enforced as written on a chain.
(define (audit l #:on [ch #f])
  (define name (resolve-chain ch 'audit))
  (audit-lock l (chain-consensus name) name))

;; Sighash search

;; (can (add-input) ...) and (fixed (outputs all) ...) quote their forms;
;; sighash-search reads them.
(define-syntax-rule (can form ...) (list 'can 'form ...))
(define-syntax-rule (fixed form ...) (list 'fixed 'form ...))

;; The flag sets each spend version accepts.
(define (flag-sets version)
  (append (if (eq? version 'v1) '((default)) '())
          '((all) (all anyonecanpay) (none) (none anyonecanpay) (single) (single anyonecanpay))))

;; The free-fields entries a goal word stands for in t.
(define (goal-edits t word)
  (define refs (for/list ([o (in-list (tx-outputs t))] [j (in-naturals)]) (or (txout-label o) j)))
  (define output-edits (append* (for/list ([r (in-list refs)]) (list `(output ,r amount) `(output ,r lock)))))
  (case (if (pair? word) (car word) word)
    [(add-input) '((inputs append))]
    [(remove-inputs) '((inputs remove-others))]
    [(add-output) '((outputs append))]
    [(change-outputs) output-edits]
    [(change-version version) '(version)]
    [(change-locktime locktime) '(locktime)]
    [(outputs) (cons '(outputs append) output-edits)]
    [(inputs) '((inputs append) (inputs remove-others))]
    [(output) (list `(output ,(second word) amount) `(output ,(second word) lock))]
    [else (raise-arguments-error 'sighash-search "unknown goal word" "word" word)]))

;; The spend types and flag sets under which t's signers could sign so that
;; every #:goal edit is free and no #:keep field is. Each signed input is
;; re-signed on a hypothetical coin of the spend type (same outpoint and
;; amount), then judged with free-fields; nothing touches the chain.
;; Returns rows (spend-type flags).
(define (sighash-search t
                        #:goal [goal (can)]
                        #:keep [keep (fixed)]
                        #:over [types '(wpkh tr-key tr-script)])
  (define signers
    (for/list ([in (in-list (tx-inputs t))])
      (for/first ([x (in-list (txin-witness in))] #:when (sig? x)) (sig-key x))))
  (unless (ormap values signers) (raise-arguments-error 'sighash-search "the tx has no signatures" "tx" t))
  (for*/list ([type (in-list types)]
              [flags (in-list (flag-sets (if (eq? type 'wpkh) 'v0 'v1)))]
              #:when (let* ([variant (resign t signers type flags)]
                            [free (free-fields variant)])
                       (and (andmap (λ (e) (member e free)) (append-map (λ (w) (goal-edits t w)) (cdr goal)))
                            (not (ormap (λ (e) (member e free)) (append-map (λ (w) (goal-edits t w)) (cdr keep)))))))
    (list type flags)))

(define search-internal (key '|search internal key|))

;; t with every signed input moved to a coin of the spend type and signed
;; again with flags.
(define (resign t signers type flags)
  (define specs
    (for/list ([in (in-list (tx-inputs t))] [k (in-list signers)])
      (define c (txin-coin in))
      (cond
        [(not k) (input c #:sequence (txin-sequence in))]
        [else
         (define-values (l path)
           (case type
             [(wpkh) (values (wpkh k) #f)]
             [(tr-key) (values (tr k) #f)]
             [(tr-script) (values (tr search-internal
                                      #:leaves (list (make-contract-instance 'single-key (list k) (policy-pk k))))
                                  'single-key)]
             [else (raise-arguments-error 'sighash-search "unknown spend type; known: wpkh tr-key tr-script"
                                          "type" type)]))
         (input (struct-copy coin c [lock l]) #:sign k #:sighash flags #:path path #:sequence (txin-sequence in))])))
  (build-tx (tx-name t) specs (tx-outputs t) #:version (tx-version t) #:locktime (tx-locktime t)))
