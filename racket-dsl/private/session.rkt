#lang racket/base
;; The live session: every chain's state, recorded traces and the scenario
;; log.
;;
;; The whole session is one immutable world value in a box, so a snapshot
;; is just the current value and restoring is putting it back.

(require racket/list
         "amount.rkt"
         "values.rkt"
         "consensus.rkt"
         "result.rkt")

(provide (struct-out chain-ref)
         make-chain!
         reset-session!
         mine
         build-tx
         spend
         try
         broadcast
         confirm
         confirmed?
         utxos
         fee
         last-trace
         scenario-log)

;; blocks is newest first; each is (list height time txids).
;; utxos maps outpoint -> utxo. mempool is in arrival order.
;; confirmed maps txid -> height.
(struct chain-state (name consensus height time blocks utxos mempool confirmed) #:transparent)

;; chains maps name -> chain-state, traces maps id -> list of events, and
;; log is the scenario log, newest first.
(struct world (chains traces log) #:transparent)

(define empty-world (world (hash) (hash) '()))
(define the-world (box empty-world))

(define (reset-session!) (set-box! the-world empty-world))

(define (current-world) (unbox the-world))

(define (update-world! f) (set-box! the-world (f (current-world))))

(define (get-chain name)
  (hash-ref (world-chains (current-world)) name
            (λ () (raise-arguments-error 'chain "no such chain" "name" name))))

(define (put-chain! cs)
  (update-world! (λ (w) (struct-copy world w [chains (hash-set (world-chains w) (chain-state-name cs) cs)]))))

;; Appends an event to the scenario log and returns its step number.
(define (log! event)
  (update-world! (λ (w) (struct-copy world w [log (cons event (world-log w))])))
  (length (world-log (current-world))))

(define (record-trace! events)
  (define id (add1 (hash-count (world-traces (current-world)))))
  (update-world! (λ (w) (struct-copy world w [traces (hash-set (world-traces w) id events)])))
  id)

(define (last-trace)
  (define traces (world-traces (current-world)))
  (hash-ref traces (hash-count traces) #f))

(define (scenario-log) (reverse (world-log (current-world))))

;; Chains

(struct chain-ref (name)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc c port mode) (write (chain-ref-name c) port))])

(define (make-chain! name c)
  (put-chain! (chain-state name c 0 (consensus-param c 'genesis-time) '() (hash) '() (hash)))
  (log! (list 'chain name (consensus-name c)))
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

(define anonymous-miner (key 'miner))

;; Returns the coinbase coins of the new blocks, always as a list.
(define (mine n #:on ch #:to [payee #f])
  (define name (resolve-chain ch 'mine))
  (define coins (for/list ([_ (in-range n)]) (mine-block! name payee)))
  (log! `(mine ,name ,n ,@(if payee (list '#:to (key-name payee)) '())))
  coins)

;; Returns the coinbase coin of the new block.
(define (mine-block! name payee)
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
                      (list (txout #f (wpkh (or payee anonymous-miner)) reward))))
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
  (output-of cb 0))

;; Building transactions

(define (build-tx name inputs outputs #:version [version 2] #:locktime [locktime 0])
  ;;* All inputs spend coins on one chain, and the tx lives on that chain.
  (when (null? inputs) (raise-arguments-error 'build-tx "a transaction needs at least one input" "name" name))
  (define spent (map input-spec-coin inputs))
  (define chain (coin-chain (first spent)))
  (unless (andmap (λ (c) (eq? (coin-chain c) chain)) spent)
    (raise-arguments-error 'build-tx "inputs spend coins on different chains" "coins" spent))
  (define c (chain-state-consensus (get-chain chain)))
  (define unsigned
    (make-tx chain name version locktime
             (for/list ([spec (in-list inputs)])
               (txin (input-spec-coin spec) (input-spec-sequence spec) '()))
             outputs))
  ;;* Sign each input that names a key, committing to the fields its spend version's selector picks.
  (define signed
    (for/list ([spec (in-list inputs)] [in (in-list (tx-inputs unsigned))] [idx (in-naturals)])
      (define k (input-spec-key spec))
      (cond
        [k
         (define select (hash-ref (consensus-sighash c) (lock-spend-version (coin-lock (input-spec-coin spec)))))
         (define fields (select unsigned idx spent (input-spec-sighash spec)))
         (struct-copy txin in [witness (list (sig k (input-spec-sighash spec) fields) k)])]
        [else in])))
  (make-tx chain name version locktime signed outputs))

;; what is a coin or a list of inputs/coins.
(define (spend what
               #:sign [k #f]
               #:sighash [type '(all)]
               #:sequence [sequence #xffffffff]
               #:locktime [locktime 0]
               #:outputs outputs)
  (define (->spec x)
    (if (input-spec? x) x (input x #:sign k #:sighash type #:sequence sequence)))
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
  (define trace (record-trace! (reverse events)))
  (define step (log! (list verb (tx-chain t) (or (tx-name t) (tx-txid t))
                           (if verdict 'rejected 'accepted))))
  (if verdict
      (rejected (tx-chain t) (first verdict) (second verdict) (third verdict) step trace)
      (accepted (tx-chain t) t step trace)))

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
