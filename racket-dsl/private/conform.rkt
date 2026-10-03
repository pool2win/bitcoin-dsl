#lang racket/base
;; Conformance replay: walk a scenario log against real nodes and give
;; every step a status.
;;
;;   confirmed   the node agrees with the model
;;   disagree    it does not; detail says what each side said
;;   unverified  the step could not be checked: no target for the chain, a
;;               consensus the target does not run, or something lowering
;;               cannot express yet (taproot)
;;
;; Nothing passes silently: a step is only confirmed after the node has
;; actually been asked.

(require racket/list
         racket/math
         file/sha1
         "amount.rkt"
         "values.rkt"
         "consensus.rkt"
         "log.rkt"
         "real/lower.rkt"
         "real/node.rkt")

(provide regtest
         (struct-out target)
         replay
         (struct-out run)
         (struct-out step)
         summary
         disagreements)

;; A node to replay a chain against. build names the implementation; only
;; core is known, and it runs consensus bitcoin.
(struct target (build bitcoind))

(define (regtest #:build [build 'core] #:bitcoind [bitcoind "bitcoind"])
  (target build bitcoind))

(define target-consensus (hash 'core 'bitcoin))

(struct step (n event status detail)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc s port mode)
     (fprintf port "(~a #:step ~a ~s~a)" (step-status s) (step-n s) (step-event s)
              (if (null? (step-detail s)) "" (format " ~s" (step-detail s)))))])

(struct run (steps)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc r port mode) (fprintf port "#<run ~s>" (summary r)))])

(define (count-status r status)
  (for/sum ([s (in-list (run-steps r))]) (if (eq? (step-status s) status) 1 0)))

(define (summary r)
  (for/list ([status '(confirmed disagree unverified)])
    (list status (count-status r status))))

(define (disagreements r)
  (filter (λ (s) (eq? (step-status s) 'disagree)) (run-steps r)))

;; targets maps chain name -> target.
(define (replay events #:targets targets)
  (define nodes (make-hasheq))
  (define txids (make-hash))
  (define (real-outpoint op)
    (define txid (hash-ref txids (outpoint-txid op)
                           (λ () (raise (exn:unsupported "cannot lower: unknown coin"
                                                         (current-continuation-marks)
                                                         "spends a coin the replay has not seen")))))
    (values txid (outpoint-vout op)))
  (dynamic-wind
   void
   (λ ()
     (run (for/list ([e (in-list events)] [i (in-naturals 1)])
            (define-values (status detail)
              (replay-event e targets nodes txids real-outpoint))
            (step i e status detail))))
   (λ () (for ([n (in-hash-values nodes)]) (stop-node n)))))

(define (event-chain e)
  (cond [(ev-chain? e) (ev-chain-name e)]
        [(ev-mine? e) (ev-mine-chain e)]
        [(ev-tx? e) (ev-tx-chain e)]))

(define (replay-event e targets nodes txids real-outpoint)
  (define chain (event-chain e))
  (define n (hash-ref nodes chain #f))
  (cond
    [(ev-chain? e) (start-chain e targets nodes)]
    [(not n) (values 'unverified (list '#:reason 'no-node-for-chain))]
    [(ev-mine? e) (replay-mine e n txids)]
    [(ev-tx? e) (replay-tx e n txids real-outpoint)]))

;; Starts a fresh node for the chain if it has a target running its rules.
(define (start-chain e targets nodes)
  (define t (hash-ref targets (ev-chain-name e) #f))
  (define rules (consensus-name (ev-chain-consensus e)))
  (cond
    [(not t) (values 'unverified (list '#:reason 'no-target))]
    [(not (eq? (hash-ref target-consensus (target-build t) #f) rules))
     (values 'unverified (list '#:reason 'target-runs-other-rules '#:build (target-build t) '#:rules rules))]
    [else
     (define n (start-node #:bitcoind (target-bitcoind t)))
     (hash-set! nodes (ev-chain-name e) n)
     (define height (rpc n "getblockcount"))
     (if (zero? height)
         (values 'confirmed '())
         (values 'disagree (list '#:model-height 0 '#:node-height height)))]))

;; Mines each block to the same payee, maps the model coinbase to the real
;; one, and checks height, reward and the set of included txs.
(define (replay-mine e n txids)
  (define spk (lower-spk (lock->spk (ev-mine-payee e))))
  (define problems
    (append*
     (for/list ([b (in-list (ev-mine-blocks e))])
       (define hash (first (rpc n "generatetodescriptor" 1 (format "raw(~a)" (bytes->hex-string spk)))))
       (define block (rpc n "getblock" hash 2))
       (define txs (hash-ref block 'tx))
       (define coinbase (first txs))
       (hash-set! txids (tx-txid (block-info-coinbase b)) (hash-ref coinbase 'txid))
       (define model-reward (amount-sats (txout-amount (first (tx-outputs (block-info-coinbase b))))))
       (define node-reward (for/sum ([o (in-list (hash-ref coinbase 'vout))]) (btc->sats (hash-ref o 'value))))
       (define model-included (sort (for/list ([t (in-list (block-info-included b))])
                                      (hash-ref txids (tx-txid t) (tx-txid t)))
                                    string<?))
       (define node-included (sort (map (λ (t) (hash-ref t 'txid)) (rest txs)) string<?))
       (append
        (if (= (hash-ref block 'height) (block-info-height b))
            '()
            (list (list 'height (block-info-height b) (hash-ref block 'height))))
        (if (= model-reward node-reward) '() (list (list 'reward model-reward node-reward)))
        (if (equal? model-included node-included) '() (list (list 'included model-included node-included)))))))
  (if (null? problems)
      (values 'confirmed '())
      (values 'disagree (list '#:mismatches problems))))

(define (btc->sats v) (exact-round (* v sats-per-btc)))

;; Lowers the tx and asks the node: testmempoolaccept for try,
;; sendrawtransaction for broadcast. maxfeerate 0 turns off the RPC's
;; client-side fee guard, which is neither consensus nor policy.
(define (replay-tx e n txids real-outpoint)
  (define t (ev-tx-tx e))
  (with-handlers ([exn:unsupported? (λ (x) (values 'unverified (list '#:reason (exn:unsupported-reason x))))])
    (define lowered (lower-tx t real-outpoint))
    (hash-set! txids (tx-txid t) (ltx-txid lowered))
    (define hex (ltx-hex lowered))
    (define node-reason
      (case (ev-tx-verb e)
        [(try)
         (define r (first (rpc n "testmempoolaccept" (list hex) 0)))
         (if (hash-ref r 'allowed) #f (hash-ref r 'reject-reason "rejected"))]
        [(broadcast)
         (with-handlers ([exn:rpc? exn-message])
           (rpc n "sendrawtransaction" hex 0)
           #f)]))
    (define verdict (ev-tx-verdict e))
    (cond
      [(eq? (not verdict) (not node-reason)) (values 'confirmed '())]
      [else
       (values 'disagree
               (list '#:model (if verdict (list 'rejected (first verdict)) 'accepted)
                     '#:node (if node-reason (list 'rejected node-reason) 'accepted)))])))
