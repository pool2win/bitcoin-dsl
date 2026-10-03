#lang bitcoin/model
;; Scenario 4: a CTV vault on two chains with different rules.

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
