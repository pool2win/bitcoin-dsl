#lang bitcoin/model
;; Scenario 3: sighash exploration and fee bumping.

(require rackunit)

(chain mainnet #:rules bitcoin)
(keys alice bob carol)

(define cb (first (mine 1 #:on mainnet #:to alice)))
(define cc (first (mine 1 #:on mainnet #:to carol)))
(mine 100 #:on mainnet)

(define-tx split                ; give carol a small fee coin
  #:inputs  ([cc #:sign carol])
  #:outputs ([fee-coin (wpkh carol) (btc 0.01)]
             [rest     (wpkh carol) (btc 49.98)]))
(check-pred accepted? (confirm split))

(define-tx pay
  #:inputs  ([cb #:sign alice #:sighash '(all anyonecanpay)])
  #:outputs ([to-bob (wpkh bob) (btc 49.99)]))

(check-equal? (commits (sig-of pay 0))
              '(version
                (own-input outpoint) (own-prevout script) (own-prevout amount) (own-input sequence)
                (outputs all)
                locktime))

(check-equal? (free-fields pay) '((inputs append) (inputs remove-others)))

(define bumped (add-input pay fee-coin #:sign carol))
(check-pred accepted? (try bumped))
(check-equal? (fee bumped) (btc 0.02))

(check-equal? (breaks-entries (mutate pay '(output to-bob amount) (btc 49.0)))
              `((sig ,alice 0 #:fields ((outputs all)))))

;; With plain SIGHASH_ALL the same bump breaks alice's signature.
(define-tx pay-all
  #:inputs  ([cb #:sign alice])
  #:outputs ([to-bob-all (wpkh bob) (btc 49.99)]))
(check-equal? (free-fields pay-all) '())
(define bad (try (add-input pay-all fee-coin #:sign carol)))
(check-equal? (rejected-rule bad) 'eval-false)
(check-equal? (result-detail bad 'cause) 'commitment-mismatch)
