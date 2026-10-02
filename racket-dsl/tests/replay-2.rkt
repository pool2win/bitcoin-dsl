#lang bitcoin/conform
;; Scenario 2, replayed against regtest Core: HTLC branches, timelocks and explained failures.

(require rackunit)

(chain mainnet #:rules bitcoin)
(keys alice bob)

(contract htlc (sender receiver secret timeout)
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(define s (secret 's1))
(define cb (first (mine 1 #:on mainnet #:to alice)))
(mine 100 #:on mainnet)

(define-tx fund
  #:inputs  ([cb #:sign alice])
  #:outputs ([locked (htlc alice bob s 144) (btc 49.99)]))
(check-pred accepted? (confirm fund))

(check-equal? (map branch-name (branches locked)) '(claim refund))
(check-equal? (map branch-needs (branches locked))
              `(((sig ,bob) (preimage ,s))
                ((sig ,alice) (age>= 144))))

(define refund
  (spend locked #:path 'refund #:sign alice
    #:outputs (list (output 'back (wpkh alice) (btc 49.98)))))

;; Too early: BIP68 holds the input back until the coin is 144 blocks deep.
(define early (try refund))
(check-equal? (rejected-rule early) 'sequence-lock)
(check-equal? (rejected-input early) 0)
(check-equal? (result-detail early 'need) 144)
(check-equal? (result-detail early 'have) 1)

;; The failing step in the explanation names the rule and carries its doc.
(define failing (last (explain (last-trace))))
(check-equal? (take failing 5) '(rule sequence-lock #:input 0 fail))
(check-not-false (memq '#:doc failing))

(define t0 (snapshot))
(mine 143 #:on mainnet)
(check-pred accepted? (try refund))
(restore t0)
(check-pred rejected? (try refund))   ; restore rewound the chain

(check-pred accepted?
            (try (spend locked #:path 'claim #:sign bob #:reveal s
                   #:outputs (list (output 'claimed (wpkh bob) (btc 49.98))))))

;; Replay against a fresh regtest node (skipped without bitcoind).
(if (find-executable-path "bitcoind")
    (let ([r (replay (scenario-log) #:targets (hash 'mainnet (regtest)))])
      (check-equal? (disagreements r) '())
      (check-equal? (cadr (assq 'unverified (summary r))) 0)
      (check-true (> (cadr (assq 'confirmed (summary r))) 0)))
    (displayln "skipping replay: bitcoind not found"))
