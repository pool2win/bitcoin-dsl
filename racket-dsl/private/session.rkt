#lang racket/base
;; The live session: every chain's state, recorded traces and the scenario
;; log.
;;
;; The whole session is one immutable world value in a box, so a snapshot
;; is just the current chains and log, and restoring puts them back. Traces
;; are kept across restores so trace ids in earlier results stay valid.
;; After a restore the log is the history of the current branch, which is
;; what a conformance replay needs.

(require racket/list
         racket/match
         racket/promise
         "amount.rkt"
         "crypto.rkt"
         "values.rkt"
         "policy.rkt"
         "script.rkt"
         "consensus.rkt"
         "log.rkt"
         "result.rkt")

(provide (struct-out chain-ref)
         current-world-box
         empty-world
         make-chain!
         reset-session!
         mine
         build-tx
         add-input
         chain-consensus
         resolve-chain
         spend
         try
         broadcast
         confirm
         confirmed?
         height
         utxos
         fee
         branches
         (struct-out trace)
         last-trace
         explain
         snapshot
         restore
         scenario-log
         session-summary)

;; blocks is newest first; each is (list height time txids).
;; utxos maps outpoint -> utxo. mempool is in arrival order.
;; confirmed maps txid -> height.
(struct chain-state (name consensus height time blocks utxos mempool confirmed) #:transparent)

;; chains maps name -> chain-state, traces maps id -> trace, and log is
;; the scenario log, newest first.
(struct world (chains traces log) #:transparent)

(define empty-world (world (hash) (hash) '()))
;; A parameter so a computation can run in a scratch world, e.g.
;; (parameterize ([current-world-box (box empty-world)]) ...).
(define current-world-box (make-parameter (box empty-world)))

(define (reset-session!) (set-box! (current-world-box) empty-world))

(define (current-world) (unbox (current-world-box)))

(define (update-world! f) (set-box! (current-world-box) (f (current-world))))

(define (get-chain name)
  (hash-ref (world-chains (current-world)) name
            (λ () (raise-arguments-error 'chain "no such chain" "name" name))))

(define (chain-consensus name) (chain-state-consensus (get-chain name)))

(define (put-chain! cs)
  (update-world! (λ (w) (struct-copy world w [chains (hash-set (world-chains w) (chain-state-name cs) cs)]))))

;; Appends an event to the scenario log and returns its step number.
(define (log! event)
  (update-world! (λ (w) (struct-copy world w [log (cons event (world-log w))])))
  (length (world-log (current-world))))

;; A validation's events, with the consensus value that produced them so
;; explain can show rule docs.
(struct trace (id chain consensus events)
  #:methods gen:custom-write
  [(define (write-proc t port mode) (fprintf port "#<trace ~a>" (trace-id t)))])

(define (record-trace! chain c events)
  (define id (add1 (hash-count (world-traces (current-world)))))
  (update-world! (λ (w) (struct-copy world w [traces (hash-set (world-traces w) id (trace id chain c events))])))
  id)

(define (get-trace t)
  (cond [(trace? t) t]
        [else (hash-ref (world-traces (current-world)) t
                        (λ () (raise-arguments-error 'explain "no such trace" "id" t)))]))

(define (last-trace)
  (define traces (world-traces (current-world)))
  (hash-ref traces (hash-count traces) #f))

(struct snapshot-value (id chains log)
  #:methods gen:custom-write
  [(define (write-proc s port mode) (fprintf port "#<snapshot ~a>" (snapshot-value-id s)))])

(define (snapshot)
  (define w (current-world))
  (snapshot-value (length (world-log w)) (world-chains w) (world-log w)))

(define (restore snap)
  (update-world! (λ (w) (struct-copy world w
                                     [chains (snapshot-value-chains snap)]
                                     [log (snapshot-value-log snap)]))))

(define (scenario-log) (reverse (world-log (current-world))))

;; Each chain's state at a glance, plus log and trace counts.
(define (session-summary)
  (define w (current-world))
  (append
   (for/list ([cs (in-list (sort (hash-values (world-chains w)) symbol<? #:key chain-state-name))])
          (list 'chain (chain-state-name cs)
                '#:rules (consensus-name (chain-state-consensus cs))
                '#:height (chain-state-height cs)
                '#:mempool (length (chain-state-mempool cs))
                '#:utxos (hash-count (chain-state-utxos cs))))
   (list (list 'log-steps (length (world-log w)))
         (list 'traces (hash-count (world-traces w))))))

;; Chains

(struct chain-ref (name)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc c port mode) (write (chain-ref-name c) port))])

(define (make-chain! name c)
  (put-chain! (chain-state name c 0 (consensus-param c 'genesis-time) '() (hash) '() (hash)))
  (log! (ev-chain name c))
  (chain-ref name))

;; With one chain in the session, queries may leave out #:on.
(define (resolve-chain ch who)
  (cond
    [(chain-ref? ch) (chain-ref-name ch)]
    [(symbol? ch) ch]
    [else
     (define names (hash-keys (world-chains (current-world))))
     (unless (= (length names) 1)
       (raise-arguments-error who "pass #:on when the session has more than one chain" "chains" names))
     (first names)]))

;; UTXO views

(define (apply-tx view t height coinbase?)
  (define spent
    (for/fold ([v view]) ([in (in-list (tx-inputs t))] #:unless (coinbase-in? in))
      (hash-remove v (txin-outpoint in))))
  (for/fold ([v spent]) ([i (in-range (length (tx-outputs t)))])
    (define c (output-of t i))
    (hash-set v (coin-outpoint c) (utxo c height coinbase?))))

;; The UTXO set as the next block would see it after the mempool.
(define (mempool-view cs)
  (for/fold ([v (chain-state-utxos cs)]) ([t (in-list (chain-state-mempool cs))])
    (apply-tx v t (add1 (chain-state-height cs)) #f)))

;; Mining

;; Coinbases mined without #:to pay this key. Its name cannot be written
;; with keys, so no user key collides with it.
(define anonymous-miner (key '|anonymous miner|))

;; Returns the coinbase coins of the new blocks, always as a list.
(define (mine n #:on ch #:to [payee #f])
  (define name (resolve-chain ch 'mine))
  (define lock (wpkh (or payee anonymous-miner)))
  (define blocks (for/list ([_ (in-range n)]) (mine-block! name lock)))
  (log! (ev-mine name lock blocks))
  (for/list ([b (in-list blocks)]) (output-of (block-info-coinbase b) 0)))

;; Returns the new block's block-info.
(define (mine-block! name lock)
  (define cs (get-chain name))
  (define c (chain-state-consensus cs))
  (define height (add1 (chain-state-height cs)))
  (define time (+ (chain-state-time cs) (consensus-param c 'block-spacing)))
  ;;* Take mempool txs in arrival order, keeping each one that still validates against the running UTXO view.
  (define-values (included view)
    (for/fold ([included '()] [view (chain-state-utxos cs)]
               #:result (values (reverse included) view))
              ([t (in-list (chain-state-mempool cs))])
      (if (validate-tx c t view height void)
          (values included view)
          (values (cons t included) (apply-tx view t height #f)))))
  ;;* Pay the subsidy plus the included fees to the payee in a coinbase unique to this height.
  (define reward (sats (+ (block-subsidy c height)
                          (amount-sats (amount-sum (map fee included))))))
  (define cb (make-tx name #f 1 0
                      (list (coinbase-in height))
                      (list (txout #f lock reward))))
  ;;* Connect the block: UTXO set, tip, clock, confirmation index; the mempool is emptied.
  (define txs (cons cb included))
  (put-chain! (struct-copy chain-state cs
                           [height height]
                           [time time]
                           [blocks (cons (list height time (map tx-txid txs)) (chain-state-blocks cs))]
                           [utxos (apply-tx view cb height #t)]
                           [mempool '()]
                           [confirmed (for/fold ([h (chain-state-confirmed cs)]) ([t (in-list txs)])
                                        (hash-set h (tx-txid t) height))]))
  (block-info height cb included))

;; Building transactions

(define (build-tx name inputs outputs #:version [version 2] #:locktime [locktime #f])
  ;;* All inputs spend coins on one chain, and the tx lives on that chain.
  (when (null? inputs) (raise-arguments-error 'build-tx "a transaction needs at least one input" "name" name))
  (define chain (coin-chain (input-spec-coin (first inputs))))
  (check-same-chain 'build-tx chain (map input-spec-coin inputs))
  (define c (chain-consensus chain))
  ;;* Each input's branch sets its nSequence, and the largest absolute lock sets nLockTime, unless given explicitly.
  (define paths (map spec-branch inputs))
  (define unsigned
    (make-tx chain name version
             (or locktime (apply max 0 (filter values (map branch-locktime paths))))
             (for/list ([spec (in-list inputs)] [b (in-list paths)])
               (txin (input-spec-coin spec) (spec-sequence spec b) '()))
             outputs))
  ;;* Sign every input against the complete unsigned tx.
  (define signed
    (for/list ([spec (in-list inputs)] [b (in-list paths)] [idx (in-naturals)])
      (sign-input c unsigned idx spec b)))
  (make-tx chain name version (tx-locktime unsigned) signed outputs))

;; Appends an input to an existing tx and signs only that input; the other
;; inputs keep their witnesses, which stay valid only if their sighash
;; types leave the input list free (anyonecanpay).
(define (add-input t c
                   #:sign [keys #f]
                   #:path [path #f]
                   #:reveal [reveal #f]
                   #:sighash [type #f]
                   #:sequence [sequence #f])
  (check-same-chain 'add-input (tx-chain t) (list c))
  (define spec (input c #:sign keys #:path path #:reveal reveal #:sighash type #:sequence sequence))
  (define b (spec-branch spec))
  (define name (and (tx-name t) (string->symbol (format "~a+input" (tx-name t)))))
  (define (with-inputs ins) (make-tx (tx-chain t) name (tx-version t) (tx-locktime t) ins (tx-outputs t)))
  (define unsigned (with-inputs (append (tx-inputs t) (list (txin c (spec-sequence spec b) '())))))
  (define idx (length (tx-inputs t)))
  (with-inputs (append (tx-inputs t) (list (sign-input (chain-consensus (tx-chain t)) unsigned idx spec b)))))

(define (check-same-chain who chain coins)
  (unless (andmap (λ (c) (eq? (coin-chain c) chain)) coins)
    (raise-arguments-error who "coins are on different chains" "chain" chain "coins" coins)))

(define (spec-branch spec) (lock-branch (coin-lock (input-spec-coin spec)) (input-spec-path spec)))

(define (spec-sequence spec b)
  (or (input-spec-sequence spec)
      (branch-sequence b)
      (if (branch-locktime b) #xfffffffe #xffffffff)))

;; Fills the branch's witness template for input idx of t: signatures from
;; the signing keys, revealed preimages, and an empty item for anything not
;; supplied, so an incomplete spend is an explained rejection.
(define (sign-input c t idx spec b)
  (define version (lock-spend-version (coin-lock (input-spec-coin spec))))
  (define type (or (input-spec-sighash spec) (if (eq? version 'v1) '(default) '(all))))
  (define fields
    (delay ((hash-ref (consensus-sighash c) version)
            t idx (map txin-coin (tx-inputs t)) type (branch-leaf b))))
  (define (fill item)
    (match item
      [(need-sig k) (if (member k (input-spec-keys spec)) (sig k type (force fields)) #"")]
      [(need-preimage s) (if (member s (input-spec-reveal spec)) s #"")]
      [_ item]))
  (struct-copy txin (list-ref (tx-inputs t) idx)
               [witness (map fill (branch-witness b))]))

;; what is a coin or a list of inputs/coins.
(define (spend what
               #:sign [keys #f]
               #:path [path #f]
               #:reveal [reveal #f]
               #:sighash [type #f]
               #:sequence [sequence #f]
               #:locktime [locktime #f]
               #:outputs outputs)
  (define (->spec x)
    (if (input-spec? x)
        x
        (input x #:sign keys #:path path #:reveal reveal #:sighash type #:sequence sequence)))
  (build-tx #f (map ->spec (if (list? what) what (list what))) outputs #:locktime locktime))

;; Validation

;; Validates t against the mempool view without changing state, recording
;; the trace and a log entry. Returns a result value.
(define (evaluate t verb)
  (define cs (get-chain (tx-chain t)))
  (define events '())
  (define verdict
    (validate-tx (chain-state-consensus cs) t (mempool-view cs) (add1 (chain-state-height cs))
                 (λ (e) (set! events (cons e events)))))
  (define tid (record-trace! (tx-chain t) (chain-state-consensus cs) (reverse events)))
  (define step
    (log! (ev-tx verb (tx-chain t) t verdict
                 (remove-duplicates (for/list ([e (in-list events)] #:when (and (eq? (car e) 'op) (sixth e))) (sixth e)))
                 (remove-duplicates (for/list ([e (in-list events)] #:when (eq? (car e) 'rule)) (second e))))))
  (if verdict
      (rejected (tx-chain t) (first verdict) (second verdict) (third verdict) step tid)
      (accepted (tx-chain t) t step tid)))

(define (try t) (evaluate t 'try))

(define (broadcast t)
  (define r (evaluate t 'broadcast))
  (when (accepted? r)
    (define cs (get-chain (tx-chain t)))
    (put-chain! (struct-copy chain-state cs [mempool (append (chain-state-mempool cs) (list t))])))
  r)

;; Broadcast, then mine one block if the tx was accepted.
(define (confirm t)
  (define r (broadcast t))
  (when (accepted? r) (mine 1 #:on (tx-chain t)))
  r)

;; Queries

;; The chain's tip height. #:on may be left out with one chain.
(define (height #:on [ch #f])
  (chain-state-height (get-chain (resolve-chain ch 'height))))

(define (confirmed? t)
  (hash-has-key? (chain-state-confirmed (get-chain (tx-chain t))) (tx-txid t)))

(define (utxo<? a b)
  (define oa (coin-outpoint (utxo-coin a)))
  (define ob (coin-outpoint (utxo-coin b)))
  (cond [(not (= (utxo-height a) (utxo-height b))) (< (utxo-height a) (utxo-height b))]
        [(not (string=? (outpoint-txid oa) (outpoint-txid ob))) (string<? (outpoint-txid oa) (outpoint-txid ob))]
        [else (< (outpoint-vout oa) (outpoint-vout ob))]))

;; Confirmed coins, by confirmation height then outpoint.
(define (utxos #:on [ch #f] #:spendable-by [k #f] #:locked-by [l #f])
  (define cs (get-chain (resolve-chain ch 'utxos)))
  (define matching
    (for/list ([u (in-hash-values (chain-state-utxos cs))]
               #:when (or (not k) (lock-spendable-by? (coin-lock (utxo-coin u)) k))
               #:when (or (not l) (equal? (coin-lock (utxo-coin u)) l)))
      u))
  (map utxo-coin (sort matching utxo<?)))

(define (fee t)
  (when (tx-coinbase? t) (raise-arguments-error 'fee "a coinbase has no fee" "tx" t))
  (sats (- (amount-sats (amount-sum (map (λ (in) (coin-amount (txin-coin in))) (tx-inputs t))))
           (amount-sats (amount-sum (map txout-amount (tx-outputs t)))))))

;; The spend paths of a coin, with what each needs.
(define (branches c) (lock-branches (coin-lock c)))

;; Explaining traces

;; A trace as readable data: one entry per rule run and per opcode run,
;; in order. Stacks are shown top first. A failing rule carries its doc.
(define (explain t)
  (define tr (get-trace t))
  (define (keywords details)
    (append* (for/list ([p (in-list details)])
               (list (string->keyword (symbol->string (car p))) (cdr p)))))
  (for/list ([e (in-list (trace-events tr))])
    (match e
      [(list 'rule name idx outcome details failed-as)
       `(rule ,name
              ,@(if idx `(#:input ,idx) '())
              ,outcome
              ,@(if failed-as `(#:as ,failed-as) '())
              ,@(keywords details)
              ,@(if (eq? outcome 'fail)
                    `(#:doc ,(failure-doc (trace-consensus tr) (or failed-as name)))
                    '()))]
      [(list 'op op before after ran _byte)
       `(op ,op
            ,@(if (and ran (not (eq? ran op))) `(#:as ,ran) '())
            #:stack ,before
            ,@(if (script-failure? after)
                  `(#:fail ,(script-failure-rule after) ,@(keywords (script-failure-details after)))
                  `(#:=> ,after)))])))
