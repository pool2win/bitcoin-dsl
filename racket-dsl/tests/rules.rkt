#lang bitcoin/model
;; Each bitcoin rule rejects with its own name and details.

(require rackunit
         (only-in "../private/values.rkt" make-tx tx-chain tx-name tx-version tx-locktime
                  tx-inputs txout)
         (only-in "../private/session.rkt" make-chain!))

(keys alice bob mallory)

;; A fresh chain with a mature 50 BTC coin for alice.
(define (funded name)
  (define ch (make-chain! name bitcoin))
  (define cb (first (mine 1 #:on ch #:to alice)))
  (mine 100 #:on ch)
  cb)

(define (pay-from c k amt)
  (spend c #:sign k #:outputs (list (output 'to-bob (wpkh bob) amt))))

(test-case "accepted spend records rule and opcode steps in the trace"
  (define cb (funded 'c1))
  (check-pred accepted? (try (pay-from cb alice (btc 49.99))))
  (define trace (trace-events (last-trace)))
  (check-not-false (member '(rule coinbase-maturity 0 pass ()) trace))
  (check-equal? (map second (filter (λ (e) (eq? (first e) 'op)) trace))
                `(dup hash160 (push ,(hash160 alice)) equalverify checksig)))

(test-case "immature coinbase"
  (define ch (make-chain! 'c2 bitcoin))
  (define cb (first (mine 1 #:on ch #:to alice)))
  (mine 50 #:on ch)
  (define r (try (pay-from cb alice (btc 49.99))))
  (check-equal? (rejected-rule r) 'coinbase-maturity)
  (check-equal? (rejected-input r) 0)
  (check-equal? (result-detail r 'need) 100)
  (check-equal? (result-detail r 'have) 51))

(test-case "outputs exceed inputs"
  (define cb (funded 'c3))
  (define r (try (pay-from cb alice (btc 51))))
  (check-equal? (rejected-rule r) 'value-balance)
  (check-equal? (result-detail r 'out) (btc 51)))

(test-case "double spend against the mempool"
  (define cb (funded 'c4))
  (check-pred accepted? (broadcast (pay-from cb alice (btc 49.99))))
  (define r (broadcast (pay-from cb alice (btc 49.98))))
  (check-equal? (rejected-rule r) 'input-exists))

(test-case "signed by a key the coin does not need"
  (define cb (funded 'c5))
  (define r (try (pay-from cb mallory (btc 49.99))))
  (check-equal? (rejected-rule r) 'eval-false)
  (check-equal? (result-detail r 'cause) 'empty-signature))

(test-case "output changed after signing"
  (define cb (funded 'c6))
  (define signed (pay-from cb alice (btc 49.99)))
  (define tampered
    (make-tx (tx-chain signed) (tx-name signed) (tx-version signed) (tx-locktime signed)
             (tx-inputs signed)
             (list (txout 'to-mallory (wpkh mallory) (btc 49.99)))))
  (define r (try tampered))
  (check-equal? (rejected-rule r) 'eval-false)
  (check-equal? (result-detail r 'cause) 'commitment-mismatch))

(test-case "unsigned input"
  (define cb (funded 'c7))
  (define r (try (spend cb #:outputs (list (output 'x (wpkh bob) (btc 49.99))))))
  (check-equal? (rejected-rule r) 'eval-false)
  (check-equal? (result-detail r 'cause) 'empty-signature))

(test-case "utxos are ordered by confirmation height"
  (define ch (make-chain! 'c8 bitcoin))
  (define coins (mine 2 #:on ch #:to bob))
  (check-equal? (length coins) 2)
  (check-equal? (utxos #:on ch #:spendable-by bob) coins))

(test-case "mine always returns a list"
  (define ch (make-chain! 'c9 bitcoin))
  (check-equal? (mine 0 #:on ch) '())
  (check-pred coin? (first (mine 1 #:on ch))))
