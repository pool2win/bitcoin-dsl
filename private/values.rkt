#lang racket/base
;; Core model values: locks, coins and transactions.

(require racket/list
         file/sha1
         "amount.rkt"
         "crypto.rkt"
         "policy.rkt")

(provide (struct-out lock)
         wpkh
         wsh
         tr
         lock->spk
         lock-spend-version
         lock-script-code
         lock-branches
         lock-branch
         lock-spendable-by?
         lock-scripts
         p2wpkh-script
         (struct-out control)
         tapleaf
         tapbranch
         taptweak
         merkle-root
         witness-leaf
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

;; Locks (output templates)

;; A lock is how the DSL describes an output: its kind and the arguments
;; it was built from. lock->spk derives what consensus actually sees.
;;   wpkh  params: (key)
;;   wsh   params: (contract-instance)
;;   tr    params: (internal-key leaves), leaves a list of contract instances
(struct lock (kind params)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc l port mode)
     (case (lock-kind l)
       [(wsh) (write (first (lock-params l)) port)]
       [(tr)
        (define leaves (second (lock-params l)))
        (fprintf port "(tr ~s~a)" (first (lock-params l))
                 (if (null? leaves) "" (format " #:leaves ~s" leaves)))]
       [else
        (fprintf port "(~a~a)" (lock-kind l)
                 (apply string-append
                        (for/list ([p (in-list (lock-params l))]) (format " ~s" p))))]))])

(define (wpkh k)
  (unless (key? k) (raise-argument-error 'wpkh "key?" k))
  (lock 'wpkh (list k)))

(define (wsh instance)
  (unless (contract-instance? instance) (raise-argument-error 'wsh "contract-instance?" instance))
  (lock 'wsh (list instance)))

;; Leaves may be contract locks (what a contract function returns) or
;; contract instances; either way the leaf script is the contract's script.
(define (tr k #:leaves [leaves '()])
  (unless (key? k) (raise-argument-error 'tr "key?" k))
  (define instances
    (for/list ([l (in-list leaves)])
      (cond [(contract-instance? l) l]
            [(and (lock? l) (eq? (lock-kind l) 'wsh)) (first (lock-params l))]
            [else (raise-argument-error 'tr "a contract" l)])))
  (lock 'tr (list k instances)))

(define (p2wpkh-script h) `(dup hash160 (push ,h) equalverify checksig))

(define (lock->spk l)
  (case (lock-kind l)
    [(wpkh) (list 'v0 (hash160 (first (lock-params l))))]
    [(wsh) (list 'v0 (sha256-of (contract-instance-script (first (lock-params l)))))]
    [(tr) (let-values ([(root paths) (tr-tree l)])
            (list 'v1 (taptweak (first (lock-params l)) root)))]))

(define (lock-spend-version l)
  (case (lock-kind l)
    [(wpkh wsh) 'v0]
    [(tr) 'v1]))

;; The script a BIP143 signature commits to.
(define (lock-script-code l)
  (case (lock-kind l)
    [(wpkh) (p2wpkh-script (second (lock->spk l)))]
    [(wsh) (contract-instance-script (first (lock-params l)))]
    [(tr) #f]))

;; Each branch's witness template is complete: for wsh it ends with the
;; witness script, for a taproot script path with the leaf script and
;; control block.
(define (lock-branches l)
  (case (lock-kind l)
    [(wpkh)
     (define k (first (lock-params l)))
     (list (branch 'default `((sig ,k)) (list (need-sig k) k) #f #f #f))]
    [(wsh)
     (define c (first (lock-params l)))
     (for/list ([b (in-list (contract-instance-branches c))])
       (struct-copy branch b [witness (append (branch-witness b) (list (contract-instance-script c)))]))]
    [(tr) (tr-branches l)]))

;; path #f picks the only branch, and is an error when there are several.
(define (lock-branch l path)
  (define bs (lock-branches l))
  (cond
    [path (or (findf (λ (b) (eq? (branch-name b) path)) bs)
              (raise-arguments-error 'spend "no such spend path" "path" path "paths" (map branch-name bs)))]
    [(= (length bs) 1) (first bs)]
    [else (raise-arguments-error 'spend "this coin has several spend paths; pass #:path"
                                 "paths" (map branch-name bs))]))

;; Every script a lock can run, each paired with whether it is tapscript.
(define (lock-scripts l)
  (case (lock-kind l)
    [(wpkh) (list (cons (p2wpkh-script (second (lock->spk l))) #f))]
    [(wsh) (list (cons (contract-instance-script (first (lock-params l))) #f))]
    [(tr) (for/list ([c (in-list (second (lock-params l)))]) (cons (contract-instance-script c) #t))]))

;; True when some branch needs signatures from k and no other key.
(define (lock-spendable-by? l k)
  (for/or ([b (in-list (lock-branches l))])
    (define sig-keys (for/list ([n (in-list (branch-needs b))] #:when (eq? (first n) 'sig)) (second n)))
    (and (pair? sig-keys) (andmap (λ (x) (equal? x k)) sig-keys))))

;; Taproot

;; A script-path control block: the internal key and the leaf's merkle
;; path (sibling hashes, leaf end first). Leaf version is always 0xc0.
(struct control (internal path)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc c port mode) (fprintf port "#<control ~s>" (control-internal c)))])

(define (tapleaf script) (hashed 'tapleaf script))

;; BIP341 hashes a branch's children in sorted order; symbolic hashes are
;; ordered by their printed form.
(define (tapbranch a b)
  (hashed 'tapbranch (sort (list a b) string<? #:key (λ (h) (format "~s" h)))))

;; root is #f for a key-only output.
(define (taptweak internal root) (hashed 'taptweak (list internal root)))

(define (merkle-root leaf path)
  (for/fold ([h leaf]) ([sibling (in-list path)]) (tapbranch h sibling)))

;; The tapleaf hash a witness spends through, or #f for a key-path spend.
(define (witness-leaf w)
  (and (>= (length w) 2)
       (control? (last w))
       (tapleaf (list-ref w (- (length w) 2)))))

;; Returns the merkle root (#f with no leaves) and each leaf's path, for a
;; balanced tree over the leaves in order.
(define (tr-tree l)
  (let build ([hashes (map (λ (c) (tapleaf (contract-instance-script c))) (second (lock-params l)))])
    (cond
      [(null? hashes) (values #f '())]
      [(null? (cdr hashes)) (values (car hashes) (list '()))]
      [else
       (define-values (left right) (split-at hashes (quotient (length hashes) 2)))
       (define-values (left-root left-paths) (build left))
       (define-values (right-root right-paths) (build right))
       (values (tapbranch left-root right-root)
               (append (map (λ (p) (append p (list right-root))) left-paths)
                       (map (λ (p) (append p (list left-root))) right-paths)))])))

;; The key path is named key. A leaf is named after its contract (with an
;; index when two leaves share one), and its branches as leaf/branch.
(define (tr-branches l)
  (define internal (first (lock-params l)))
  (define leaves (second (lock-params l)))
  (define-values (root paths) (tr-tree l))
  (define names (map contract-instance-name leaves))
  (define (leaf-name c i)
    (if (> (length (filter (λ (n) (eq? n (contract-instance-name c))) names)) 1)
        (format "~a-~a" (contract-instance-name c) i)
        (format "~a" (contract-instance-name c))))
  (cons
   (branch 'key `((sig ,internal)) (list (need-sig internal)) #f #f #f)
   (for*/list ([(c i) (in-parallel leaves (in-naturals))]
               [path (in-value (list-ref paths i))]
               [b (in-list (contract-instance-branches c))])
     (define script (contract-instance-script c))
     (branch (if (eq? (branch-name b) 'default)
                 (string->symbol (leaf-name c i))
                 (string->symbol (format "~a/~a" (leaf-name c i) (branch-name b))))
             (branch-needs b)
             (append (branch-witness b) (list script (control internal path)))
             (branch-sequence b)
             (branch-locktime b)
             (tapleaf script)))))

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

;; witness is the list of witness items, bottom of the stack first.
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

;; What the author asked for on one input, before the tx is built and
;; signed. keys and reveal are lists; sequence #f means "set by the path"
;; and sighash #f the spend version's default (all, or taproot's default).
(struct input-spec (coin keys sighash sequence path reveal) #:transparent)

(define (->list x) (cond [(not x) '()] [(list? x) x] [else (list x)]))

(define (input c
               #:sign [keys #f]
               #:sighash [type #f]
               #:sequence [sequence #f]
               #:path [path #f]
               #:reveal [reveal #f])
  (unless (coin? c) (raise-argument-error 'input "coin?" c))
  (input-spec c (->list keys) (and type (sighash-flags type)) sequence path (->list reveal)))
