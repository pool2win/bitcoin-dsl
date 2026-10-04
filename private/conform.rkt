#lang racket/base
;; Conformance replay: walk a scenario log against real nodes and give
;; every step a status.
;;
;;   confirmed   the node agrees with the model
;;   disagree    it does not; detail says what each side said
;;   unverified  the step could not be checked: no target for the chain,
;;               the step exercises a rule the target runs differently
;;               (model-only-rule), it depends on such a step, or lowering
;;               cannot express it
;;
;; Nothing passes silently: a step is only confirmed after the node has
;; actually been asked. Verdicts are about consensus: when the mempool
;; rejects a tx, replay asks whether a block containing it would be valid
;; (generateblock without submitting) and uses that answer.

(require racket/list
         racket/math
         file/sha1
         "amount.rkt"
         "crypto.rkt"
         "values.rkt"
         "policy.rkt"
         "session.rkt"
         "inspect.rkt"
         "result.rkt"
         "script.rkt"
         "consensus.rkt"
         "compose.rkt"
         "proposals.rkt"
         "log.rkt"
         "real/lower.rkt"
         "real/node.rkt")

(provide regtest
         (struct-out target)
         replay
         (struct-out run)
         (struct-out step)
         summary
         disagreements
         unverified-steps
         inquisition-consensus
         sighash-matrix)

;; A node to replay a chain against: which build, its binary, the consensus
;; it runs (as a model consensus value), and deployments that must be
;; active on it.
(struct target (build bitcoind consensus deployments))

;; Inquisition activates CTV (and more) on regtest; the model knows CTV.
(define inquisition-consensus
  (extend-consensus bitcoin 'inquisition '((upgrade nop4 ctv))))

(define (default-inquisition-bitcoind)
  (or (getenv "BITCOIN_INQUISITION")
      (path->string (build-path (find-system-path 'home-dir)
                                "projects" "bitcoin-inquisition" "build" "bin" "bitcoind"))))

(define (regtest #:build [build 'core] #:bitcoind [bitcoind #f])
  (case build
    [(core) (target 'core (or bitcoind "bitcoind") bitcoin '())]
    [(inquisition) (target 'inquisition (or bitcoind (default-inquisition-bitcoind))
                           inquisition-consensus '("checktemplateverify"))]
    [else (raise-arguments-error 'regtest "unknown build; known: core, inquisition" "build" build)]))

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

(define (unverified-steps r)
  (filter (λ (s) (eq? (step-status s) 'unverified)) (run-steps r)))

;; Replay state for one chain. gate-ops and gate-rules are the opcode
;; bytes and rule names where the chain's consensus differs from the
;; target's. mempool holds real txids the node accepted since the last
;; block; pending holds raw txs the mempool refused but a block would
;; accept, so they are mined with the next block.
(struct chain-replay (node consensus gate-ops gate-rules [mempool #:mutable] [pending #:mutable]))

;; targets maps chain name -> target.
(define (replay events #:targets targets)
  (define chains (make-hasheq))
  ;; (chain . model txid) -> real txid, for every tx the node has seen.
  (define txids (make-hash))
  (define custodian (make-custodian))
  (dynamic-wind
   void
   (λ ()
     (run (for/list ([e (in-list events)] [i (in-naturals 1)])
            (define-values (status detail)
              (parameterize ([current-custodian custodian])
                (replay-event e targets chains txids)))
            (step i e status detail))))
   (λ ()
     (for ([cr (in-hash-values chains)] #:when (chain-replay-node cr)) (stop-node (chain-replay-node cr)))
     (custodian-shutdown-all custodian))))

(define (event-chain e)
  (cond [(ev-chain? e) (ev-chain-name e)]
        [(ev-mine? e) (ev-mine-chain e)]
        [(ev-tx? e) (ev-tx-chain e)]))

(define (replay-event e targets chains txids)
  (define chain (event-chain e))
  (define cr (hash-ref chains chain #f))
  (cond
    [(ev-chain? e) (start-chain e targets chains)]
    [(not cr) (values 'unverified (list '#:reason 'no-node-for-chain))]
    [(ev-mine? e) (replay-mine e cr txids)]
    [(ev-tx? e) (replay-tx e cr txids)]))

;; Starts a fresh node for the chain and works out where its rules differ
;; from the chain's.
(define (start-chain e targets chains)
  (define t (hash-ref targets (ev-chain-name e) #f))
  (cond
    [(not t) (values 'unverified (list '#:reason 'no-target))]
    [(not (find-executable-path (target-bitcoind t)))
     (values 'unverified (list '#:reason 'target-binary-missing '#:bitcoind (target-bitcoind t)))]
    [else
     (define c (ev-chain-consensus e))
     (define diff (diff-consensus (target-consensus t) c))
     (define n (start-node #:bitcoind (target-bitcoind t)))
     (hash-set! chains (ev-chain-name e)
                (chain-replay n c
                              (for/list ([d (in-list diff)] #:when (opcode-change? d)) (opcode-change-byte d))
                              (for/list ([d (in-list diff)] #:when (and (pair? d) (eq? (car d) 'rule))) (third d))
                              '() '()))
     (define inactive (inactive-deployments n (target-deployments t)))
     (define height (rpc n "getblockcount"))
     (cond
       [(pair? inactive) (values 'unverified (list '#:reason 'deployment-inactive '#:deployments inactive))]
       [(zero? height) (values 'confirmed '())]
       [else (values 'disagree (list '#:model-height 0 '#:node-height height))])]))

(define (inactive-deployments n names)
  (if (null? names)
      '()
      (let ([info (hash-ref (rpc n "getdeploymentinfo") 'deployments)])
        (for/list ([name (in-list names)]
                   #:unless (hash-ref (hash-ref info (string->symbol name) (hash)) 'active #f))
          name))))

(define (real-txid txids chain t) (hash-ref txids (cons chain (tx-txid t)) #f))

;; Mines each block to the same payee, maps the model coinbase to the real
;; one, and checks height, reward and the set of included txs. The first
;; block also takes txs the mempool refused but consensus allows. A block
;; that includes a tx the replay could not check is itself unverified.
(define (replay-mine e cr txids)
  (define chain (ev-mine-chain e))
  (define n (chain-replay-node cr))
  (define payee (format "raw(~a)" (bytes->hex-string (lower-spk (lock->spk (ev-mine-payee e))))))
  (define-values (problems unchecked)
    (for/fold ([problems '()] [unchecked '()]) ([b (in-list (ev-mine-blocks e))])
      (define hash
        (if (pair? (chain-replay-pending cr))
            (hash-ref (rpc n "generateblock" payee (append (chain-replay-mempool cr) (chain-replay-pending cr))) 'hash)
            (first (rpc n "generatetodescriptor" 1 payee))))
      (set-chain-replay-mempool! cr '())
      (set-chain-replay-pending! cr '())
      (define block (rpc n "getblock" hash 2))
      (define txs (hash-ref block 'tx))
      (define coinbase (first txs))
      (hash-set! txids (cons chain (tx-txid (block-info-coinbase b))) (hash-ref coinbase 'txid))
      (define model-included (map (λ (t) (real-txid txids chain t)) (block-info-included b)))
      (cond
        [(memq #f model-included)
         (values problems (cons (block-info-height b) unchecked))]
        [else
         (define model-reward (amount-sats (txout-amount (first (tx-outputs (block-info-coinbase b))))))
         (define node-reward (for/sum ([o (in-list (hash-ref coinbase 'vout))]) (btc->sats (hash-ref o 'value))))
         (define node-included (sort (map (λ (t) (hash-ref t 'txid)) (rest txs)) string<?))
         (values
          (append problems
                  (if (= (hash-ref block 'height) (block-info-height b))
                      '()
                      (list (list 'height (block-info-height b) (hash-ref block 'height))))
                  (if (= model-reward node-reward) '() (list (list 'reward model-reward node-reward)))
                  (if (equal? (sort model-included string<?) node-included)
                      '()
                      (list (list 'included (sort model-included string<?) node-included))))
          unchecked)])))
  (cond
    [(pair? problems) (values 'disagree (list '#:mismatches problems))]
    [(pair? unchecked) (values 'unverified (list '#:reason 'includes-unverified-tx '#:heights (reverse unchecked)))]
    [else (values 'confirmed '())]))

(define (btc->sats v) (exact-round (* v sats-per-btc)))

;; Lowers the tx and asks the node: testmempoolaccept for try,
;; sendrawtransaction for broadcast. If the mempool refuses it, the verdict
;; comes from a block check instead. maxfeerate 0 turns off the RPC's
;; client-side fee guard, which is neither consensus nor policy.
(define (replay-tx e cr txids)
  (define t (ev-tx-tx e))
  (define chain (ev-tx-chain e))
  (define n (chain-replay-node cr))
  (define (real-outpoint op)
    (define txid (hash-ref txids (cons chain (outpoint-txid op))
                           (λ () (raise (exn:unsupported "cannot lower: unknown coin"
                                                         (current-continuation-marks)
                                                         'spends-unverified-coin)))))
    (values txid (outpoint-vout op)))
  (define differs (exercised-differences e cr))
  (cond
    [(pair? differs) (values 'unverified (list '#:reason (cons 'model-only-rule differs)))]
    [else
     (with-handlers ([exn:unsupported? (λ (x) (values 'unverified (list '#:reason (exn:unsupported-reason x))))])
       (define lowered (lower-tx t real-outpoint))
       (define hex (ltx-hex lowered))
       (define mempool-reason
         (case (ev-tx-verb e)
           [(try)
            (define r (first (rpc n "testmempoolaccept" (list hex) 0)))
            (if (hash-ref r 'allowed) #f (hash-ref r 'reject-reason "rejected"))]
           [(broadcast)
            (with-handlers ([exn:rpc? exn-message])
              (rpc n "sendrawtransaction" hex 0)
              #f)]))
       (define node-reason (and mempool-reason (block-check cr hex)))
       ;;* Record what the node now holds: accepted broadcasts in its mempool, or pending for the next block.
       (when (eq? (ev-tx-verb e) 'broadcast)
         (cond [(not mempool-reason)
                (set-chain-replay-mempool! cr (append (chain-replay-mempool cr) (list (ltx-txid lowered))))]
               [(not node-reason)
                (set-chain-replay-pending! cr (append (chain-replay-pending cr) (list hex)))]))
       (when (or (eq? (ev-tx-verb e) 'try) (not node-reason))
         (hash-set! txids (cons chain (tx-txid t)) (ltx-txid lowered)))
       (define verdict (ev-tx-verdict e))
       (define mempool-note (if (and mempool-reason (not node-reason)) (list '#:mempool-only mempool-reason) '()))
       (cond
         [(eq? (not verdict) (not node-reason)) (values 'confirmed mempool-note)]
         [else
          (values 'disagree
                  (append (list '#:model (if verdict (list 'rejected (first verdict)) 'accepted)
                                '#:node (if node-reason (list 'rejected node-reason) 'accepted))
                          mempool-note))]))]))

;; The opcodes (by the chain's names) and rules this step exercised that
;; the target runs differently.
(define (exercised-differences e cr)
  (define c (chain-replay-consensus cr))
  (append
   (for/list ([b (in-list (ev-tx-opcodes e))] #:when (memv b (chain-replay-gate-ops cr)))
     (let ([oc (hash-ref (consensus-opcodes c) b #f)]) (if oc (opcode-name oc) b)))
   (for/list ([r (in-list (ev-tx-rules e))] #:when (memq r (chain-replay-gate-rules cr))) r)))

;; Would a block with the node's mempool, the pending txs and hex be valid?
;; #f if so, else the node's reason code. The block is checked, not
;; submitted.
(define (block-check cr hex)
  (with-handlers ([exn:rpc? (λ (x) (block-reason (exn-message x)))])
    (rpc (chain-replay-node cr) "generateblock" "raw(51)"
         (append (chain-replay-mempool cr) (chain-replay-pending cr) (list hex))
         #f)
    #f))

;; "generateblock: TestBlockValidity failed: bad-txns-..., detail" -> "bad-txns-..."
(define (block-reason message)
  (define m (regexp-match #rx"TestBlockValidity failed: ([^,]*)" message))
  (if m (cadr m) message))

;; Sighash matrix

;; For each spend type and flag set: two inputs signed with those flags,
;; tried unedited and under each edit, in a scratch session (the caller's
;; session is untouched); then the scratch log is replayed against target.
;; Rows are (status #:type t #:flags f #:edit e #:model verdict ...),
;; status as in replay, or (unsupported #:type t) for spend types the
;; model does not have.
(define (sighash-matrix #:spend-types [types '(wpkh tr-key tr-script)]
                        #:flags [flags 'all]
                        #:target [target (regtest)])
  (define supported (filter (λ (t) (memq t '(wpkh tr-key tr-script))) types))
  (define unsupported (for/list ([t (in-list types)] #:unless (memq t supported)) (list 'unsupported '#:type t)))
  (parameterize ([current-world-box (box empty-world)])
    ;;* Fund each signer with one coin per spend type, plus a spare coin for appended inputs.
    (define ch (make-chain! 'matrix bitcoin))
    (define-values (alice bob carol dave) (values (key 'alice) (key 'bob) (key 'carol) (key 'dave)))
    (define spare (first (mine 1 #:on ch #:to dave)))
    (define funding (for/list ([k (list alice bob)]) (cons k (first (mine 1 #:on ch #:to k)))))
    (void (mine 100 #:on ch))
    (define internal (key '|matrix internal key|))
    (define (lock-for type k)
      (case type
        [(wpkh) (wpkh k)]
        [(tr-key) (tr k)]
        [(tr-script) (tr internal #:leaves (list (make-contract-instance 'single-key (list k) (policy-pk k))))]))
    (define coins
      (for/hash ([f (in-list funding)])
        (define k (car f))
        (define t (spend (cdr f) #:sign k
                         #:outputs (for/list ([type (in-list supported)]) (output type (lock-for type k) (btc 16)))))
        (confirm t)
        (values k (for/hash ([type (in-list supported)]) (values type (out t type))))))
    ;;* Try every cell: the base tx, then each edit, remembering which log step each try was.
    (define cells
      (append*
       (for*/list ([type (in-list supported)]
                   [fl (in-list (if (eq? flags 'all) (flag-sets (if (eq? type 'wpkh) 'v0 'v1)) flags))]
                   #:unless (and (eq? type 'wpkh) (equal? fl '(default))))
         (define path (and (eq? type 'tr-script) 'single-key))
         (define base
           (spend (for/list ([k (list alice bob)])
                    (input (hash-ref (hash-ref coins k) type) #:sign k #:sighash fl #:path path))
                  #:outputs (list (output 'a (wpkh carol) (btc 5)) (output 'b (wpkh carol) (btc 5)))))
         (for/list ([e (in-list (matrix-edits base spare dave))])
           (define r (try ((cdr e) base)))
           (list (if (accepted? r) (accepted-step r) (rejected-step r)) type fl (car e)
                 (if (accepted? r) 'accepted (list 'rejected (rejected-rule r))))))))
    ;;* Replay the scratch log and read each cell's status from its step.
    (define r (replay (scenario-log) #:targets (hash 'matrix target)))
    (define by-step (for/hash ([s (in-list (run-steps r))]) (values (step-n s) s)))
    (append
     (for/list ([c (in-list cells)])
       (define s (hash-ref by-step (first c)))
       (append (list (step-status s) '#:type (second c) '#:flags (third c) '#:edit (fourth c)
                     '#:model (fifth c))
               (step-detail s)))
     unsupported)))

;; (name . tx -> edited tx) for every edit the matrix tries.
(define (matrix-edits base spare spare-key)
  (define other (wpkh (key '|matrix other|)))
  (append
   (list (cons 'none values)
         (cons '(inputs append) (λ (t) (add-input t spare #:sign spare-key)))
         (cons '(inputs remove 1) (λ (t) (edit t '(inputs remove 1))))
         (cons '(outputs append) (λ (t) (edit t '(outputs append) (output 'c other (btc 1)))))
         (cons '(outputs remove 1) (λ (t) (edit t '(outputs remove 1)))))
   (for*/list ([j '(0 1)] [field '(amount lock)])
     (cons `(output ,j ,field)
           (λ (t) (edit t `(output ,j ,field) (if (eq? field 'amount) (btc 4.9) other)))))
   (for/list ([i '(0 1)])
     (cons `(input ,i sequence) (λ (t) (edit t `(input ,i sequence) #xfffffffe))))
   (list (cons 'version (λ (t) (edit t 'version 1)))
         (cons 'locktime (λ (t) (edit t 'locktime 1))))))
