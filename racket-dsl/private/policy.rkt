#lang racket/base
;; Contracts: a small policy language compiled to segwit v0 witness scripts,
;; and the spend paths (branches) each policy offers.
;;
;; Fragments compile in one of two forms, as in miniscript: B leaves one
;; true or false item on the stack, V either succeeds leaving nothing or
;; aborts the script. A whole policy compiles to B.

(require racket/list
         racket/match
         racket/string
         "crypto.rkt")

(provide (struct-out p-pk)
         (struct-out p-sha256)
         (struct-out p-older)
         (struct-out p-after)
         (struct-out p-and)
         (struct-out p-or)
         (struct-out p-thresh)
         (struct-out p-ctv)
         policy-pk
         policy-sha256
         policy-older
         policy-after
         policy-and
         policy-or
         policy-thresh
         (struct-out branch)
         (struct-out need-sig)
         (struct-out need-preimage)
         (struct-out contract-instance)
         make-contract-instance)

;; Policy fragments

(struct p-pk (key) #:transparent)
;; digest is (sha256-of preimage); preimage is the secret when known.
(struct p-sha256 (digest preimage) #:transparent)
(struct p-older (blocks) #:transparent)
(struct p-after (height) #:transparent)
(struct p-and (subs) #:transparent)
;; arms is a list of (cons label-or-#f policy).
(struct p-or (arms) #:transparent)
(struct p-thresh (k subs) #:transparent)
;; A CTV template check. hash is the template's hash; template is kept for
;; branch needs; sequence and locktime (or #f) are what the template fixes,
;; so #:path sets them. Built by policy-ctv in proposals.rkt.
(struct p-ctv (hash template sequence locktime) #:transparent)

(define (policy-pk k)
  (unless (key? k) (raise-argument-error 'pk "key?" k))
  (p-pk k))

(define (policy-sha256 v)
  (cond [(secret? v) (p-sha256 (sha256-of v) v)]
        [(and (hashed? v) (eq? (hashed-fn v) 'sha256)) (p-sha256 v #f)]
        [else (raise-argument-error 'sha256 "(or/c secret? sha256 digest)" v)]))

;; Only block-based relative locks for now; time-based ones are unsupported.
(define (policy-older n)
  (unless (and (exact-integer? n) (<= 1 n #xffff))
    (raise-argument-error 'older "block count in [1, 65535]" n))
  (p-older n))

;; Only height-based absolute locks for now; time-based ones are unsupported.
(define (policy-after n)
  (unless (and (exact-integer? n) (<= 1 n 499999999))
    (raise-argument-error 'after "block height in [1, 499999999]" n))
  (p-after n))

(define (policy-and subs) (p-and subs))

(define (policy-or arms)
  (when (< (length arms) 2) (raise-arguments-error 'or "needs at least two arms" "arms" arms))
  (p-or arms))

(define (policy-thresh k subs)
  (unless (andmap p-pk? subs)
    (raise-arguments-error 'thresh "only thresholds over pk are supported so far" "subs" subs))
  (unless (and (exact-integer? k) (<= 1 k (length subs)))
    (raise-argument-error 'thresh (format "integer in [1, ~a]" (length subs)) k))
  (p-thresh k subs))

;; Compilation to Script

(define (compile-b p)
  (match p
    [(p-pk k) `((push ,k) checksig)]
    [(p-sha256 h _) `(size (push 32) equalverify sha256 (push ,h) equal)]
    [(p-older n) `((push ,n) csv)]
    [(p-after n) `((push ,n) cltv)]
    [(p-and subs) (append (append-map compile-v (drop-right subs 1)) (compile-b (last subs)))]
    [(p-or arms) (compile-or (map cdr arms))]
    [(p-thresh k subs) (append (compile-thresh-sum subs) `((push ,k) equal))]
    [(p-ctv h _ _ _) `((push ,h) ctv)]))

(define (compile-v p)
  (match p
    [(p-pk k) `((push ,k) checksigverify)]
    [(p-sha256 h _) `(size (push 32) equalverify sha256 (push ,h) equalverify)]
    [(p-older n) `((push ,n) csv drop)]
    [(p-after n) `((push ,n) cltv drop)]
    [(p-and subs) (append-map compile-v subs)]
    [(p-or _) (append (compile-b p) '(verify))]
    [(p-thresh k subs) (append (compile-thresh-sum subs) `((push ,k) equalverify))]
    [(p-ctv h _ _ _) `((push ,h) ctv drop)]))

;; n arms become nested IFs; the witness picks an arm with selector items.
(define (compile-or subs)
  (if (null? (cdr subs))
      (compile-b (car subs))
      `(if ,@(compile-b (car subs)) else ,@(compile-or (cdr subs)) endif)))

;; Counts valid signatures: <k1> CHECKSIG SWAP <k2> CHECKSIG ADD ...
(define (compile-thresh-sum subs)
  (append `((push ,(p-pk-key (car subs))) checksig)
          (append-map (λ (p) `(swap (push ,(p-pk-key p)) checksig add)) (cdr subs))))

;; Satisfactions

;; Witness template placeholders, filled in when the spend is signed.
(struct need-sig (key) #:transparent)
(struct need-preimage (secret) #:transparent)

;; One way to satisfy a fragment. labels are the arm names chosen at each
;; or; witness is the template, bottom of the stack first; sequence and
;; locktime are what the nSequence and nLockTime fields must be, or #f.
(struct sat (labels needs witness sequence locktime))

(define empty-sat (sat '() '() '() #f #f))

(define (max/f a b) (if (and a b) (max a b) (or a b)))

;; a's script runs before b's, so a's witness items sit above b's.
(define (sat-and a b)
  (sat (append (sat-labels a) (sat-labels b))
       (append (sat-needs a) (sat-needs b))
       (append (sat-witness b) (sat-witness a))
       (max/f (sat-sequence a) (sat-sequence b))
       (max/f (sat-locktime a) (sat-locktime b))))

;; Arm i of n nested IFs: the outer i IFs must be false (empty), then the
;; next one true (1). The last arm takes all n-1 IFs false.
(define (selectors i n)
  (if (= i (sub1 n))
      (make-list i #"")
      (cons 1 (make-list i #""))))

(define (sats p)
  (match p
    [(p-pk k) (list (sat '() `((sig ,k)) (list (need-sig k)) #f #f))]
    [(p-sha256 h s)
     (define pre (or s h))
     (list (sat '() `((preimage ,pre)) (list (need-preimage pre)) #f #f))]
    [(p-older n) (list (sat '() `((age>= ,n)) '() n #f))]
    [(p-after n) (list (sat '() `((height>= ,n)) '() #f n))]
    [(p-ctv _ t seq lt) (list (sat '() `((template ,t)) '() seq lt))]
    [(p-and subs)
     (for/fold ([acc (list empty-sat)]) ([q (in-list subs)])
       (for*/list ([a (in-list acc)] [b (in-list (sats q))]) (sat-and a b)))]
    [(p-or arms)
     (define n (length arms))
     (for*/list ([i (in-range n)]
                 [arm (in-value (list-ref arms i))]
                 [s (in-list (sats (cdr arm)))])
       (struct-copy sat s
                    [labels (cons (or (car arm) i) (sat-labels s))]
                    [witness (append (sat-witness s) (selectors i n))]))]
    [(p-thresh k subs)
     (define keys (map p-pk-key subs))
     (for/list ([chosen (in-combinations keys k)])
       (sat (list (string->symbol (string-join (map (λ (k) (symbol->string (key-name k))) chosen) "+")))
            (for/list ([k (in-list chosen)]) `(sig ,k))
            (for/list ([k (in-list (reverse keys))])
              (if (memq k chosen) (need-sig k) #""))
            #f #f))]))

;; Branches

;; A named spend path. needs is what the spender must supply, e.g.
;; ((sig bob) (preimage s1) (age>= 144)). leaf is the tapleaf hash for a
;; taproot script path, else #f.
(struct branch (name needs witness sequence locktime leaf)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc b port mode)
     (fprintf port "(~a #:needs ~s)" (branch-name b) (branch-needs b)))])

(define (sat->branch s)
  (define name
    (if (null? (sat-labels s))
        'default
        (string->symbol (string-join (map (λ (l) (format "~a" l)) (sat-labels s)) "/"))))
  (branch name (sat-needs s) (sat-witness s) (sat-sequence s) (sat-locktime s) #f))

;; Contract instances

;; A contract applied to its arguments: what a wsh lock holds.
(struct contract-instance (name args policy script branches)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc c port mode)
     (fprintf port "(~a~a)" (contract-instance-name c)
              (apply string-append
                     (for/list ([a (in-list (contract-instance-args c))]) (format " ~s" a)))))])

(define (make-contract-instance name args policy)
  (contract-instance name args policy (compile-b policy) (map sat->branch (sats policy))))

