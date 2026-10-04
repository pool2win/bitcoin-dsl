#lang bitcoin/model
;; Scenario 1: fund and spend on one chain.

(require rackunit)

(chain mainnet #:rules bitcoin)
(keys alice bob)

(define cb (first (mine 1 #:on mainnet #:to alice)))  ; mine returns a list of coinbase coins
(mine 100 #:on mainnet)                               ; mature it

(define-tx pay
  #:inputs  ([cb #:sign alice])
  #:outputs ([to-bob (wpkh bob)   (btc 49.99)]
             [change (wpkh alice) (btc 0.009)]))

(check-pred accepted? (broadcast pay))
(mine 1 #:on mainnet)

(check-true (confirmed? pay))
(check-equal? (utxos #:spendable-by bob) (list to-bob))
(check-equal? (fee pay) (btc 0.001))
(check-equal? to-bob (out pay 'to-bob))
(check-equal? change (output-of pay 1))
