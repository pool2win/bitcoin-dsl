#lang bitcoin/conform
;; Scenario 4, replayed: mainnet against Core, the CTV chain against
;; Bitcoin Inquisition, and the CTV chain against Core (which cannot check
;; CTV steps).

(require rackunit)

(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))

(chain mainnet #:rules bitcoin)
(chain signet #:rules ctv-rules)
(keys alice cold mallory)
(check-equal? (format "~s" (diff-consensus bitcoin ctv-rules)) "((opcode #xb3 nop4 -> ctv))")

(define tmpl
  (template #:outputs (list (output 'to-cold (wpkh cold) (btc 49.98)))))
(contract vault () (ctv tmpl))

(define results
  (for/list ([ch (list mainnet signet)])
    (define cb (first (mine 1 #:on ch #:to alice)))
    (void (mine 100 #:on ch))
    (define-tx lock
      #:inputs  ([cb #:sign alice])
      #:outputs ([vaulted (vault) (btc 49.99)]))
    (confirm lock)
    (list (try (spend vaulted            ; thief ignores the template
                 #:outputs (list (output 'stolen (wpkh mallory) (btc 49.98)))))
          (try (spend vaulted            ; the honest spend follows it
                 #:outputs (list (output 'to-cold (wpkh cold) (btc 49.98))))))))

(define thief (map first results))
(check-pred accepted? (first thief))                                ; covenant unenforced
(check-equal? (rejected-rule (second thief)) 'ctv-template-mismatch)
(check-equal? (rejected-chain (second thief)) 'signet)
(check-true (andmap accepted? (map second results)))

(check-equal? (audit (vault) #:on mainnet)
              '((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4)))
(check-equal? (audit (vault) #:on signet) '())

(define inquisition (regtest #:build 'inquisition))
(define have-core (find-executable-path "bitcoind"))
(define have-inquisition (find-executable-path (target-bitcoind inquisition)))

(define (statuses r) (map (λ (s) (list (step-n s) (step-status s))) (run-steps r)))

(if (and have-core have-inquisition)
    (let ([r (replay (scenario-log) #:targets (hash 'mainnet (regtest) 'signet inquisition))])
      (check-equal? (disagreements r) '())
      (check-equal? (cadr (assq 'unverified (summary r))) 0 (format "~s" (run-steps r)))
      ;; The thief's NOP4 spend on mainnet: Core's mempool refuses it as
      ;; non-standard, but a block would accept it, as the model says.
      (check-not-false
       (for/or ([s (run-steps r)])
         (and (eq? (step-status s) 'confirmed) (memq '#:mempool-only (step-detail s))))))
    (displayln "skipping Core+Inquisition replay: a binary is missing"))

(if have-core
    (let* ([r (replay (scenario-log) #:targets (hash 'mainnet (regtest) 'signet (regtest)))]
           [unverified (filter (λ (s) (eq? (step-status s) 'unverified)) (run-steps r))])
      (check-equal? (disagreements r) '())
      ;; Only the two signet spends that run CTV are unverified.
      (check-equal? (map step-detail unverified)
                    '((#:reason (model-only-rule ctv)) (#:reason (model-only-rule ctv)))))
    (displayln "skipping Core replay: bitcoind not found"))
