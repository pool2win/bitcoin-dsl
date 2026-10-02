#lang bitcoin/conform
;; Replay reports disagreements and unverified steps instead of passing
;; them silently.

(require rackunit
         (only-in "../private/consensus.rkt" consensus consensus-params))

;; A model that is wrong on purpose: coinbase outputs mature after 50
;; blocks, but it still claims to be bitcoin.
(define lax
  (struct-copy consensus bitcoin
               [params (hash-set (consensus-params bitcoin) 'coinbase-maturity 50)]))

(chain mainnet #:rules lax)
(chain elsewhere #:rules bitcoin)
(keys alice bob)

(define cb (first (mine 1 #:on mainnet #:to alice)))
(mine 60 #:on mainnet)
(check-pred accepted? (try (spend cb #:sign alice #:outputs (list (output 'b (wpkh bob) (btc 49.99))))))
(mine 50 #:on mainnet)
(check-pred accepted? (try (spend cb #:sign alice #:outputs (list (output 't (tr bob) (btc 49.99))))))
(mine 1 #:on elsewhere)

(if (find-executable-path "bitcoind")
    (let* ([r (replay (scenario-log) #:targets (hash 'mainnet (regtest)))]
           [status (for/hash ([s (run-steps r)]) (values (step-n s) s))])
      (check-equal? (summary r) '((confirmed 5) (disagree 1) (unverified 2)))
      ;; The premature coinbase spend: the model accepts, Core does not.
      (check-equal? (step-status (hash-ref status 5)) 'disagree)
      (check-equal? (step-detail (hash-ref status 5))
                    '(#:model accepted #:node (rejected "bad-txns-premature-spend-of-coinbase")))
      ;; A spend to a taproot output is lowered and checked.
      (check-equal? (step-status (hash-ref status 7)) 'confirmed)
      ;; The second chain has no target.
      (check-equal? (step-detail (hash-ref status 2)) '(#:reason no-target))
      (check-equal? (step-status (hash-ref status 8)) 'unverified))
    (displayln "skipping replay: bitcoind not found"))
