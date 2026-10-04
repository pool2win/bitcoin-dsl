#lang bitcoin/model
;; Consensus composition: define-consensus and diff-consensus.

(require rackunit
         (only-in "../private/consensus.rkt" consensus-param consensus-rule consensus-parent rule rule-name)
         (only-in "../private/compose.rkt" registered-consensus))

(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))

(check-equal? (format "~s" (diff-consensus bitcoin ctv-rules)) "((opcode #xb3 nop4 -> ctv))")
(check-equal? (format "~s" (diff-consensus ctv-rules bitcoin)) "((opcode #xb3 ctv -> nop4))")
(check-equal? (diff-consensus bitcoin bitcoin) '())
(check-eq? (consensus-parent ctv-rules) bitcoin)
(check-eq? (registered-consensus 'ctv-rules) ctv-rules)

(define no-op-rule (rule 'always-ok 'tx "Never fails." (λ (x) #f)))
(define lax-balance (rule 'value-balance 'tx "Anything goes." (λ (x) #f)))

(define-consensus tweaked #:extends ctv-rules
  #:params (set coinbase-maturity 50)
  #:rules (remove duplicate-inputs) (add no-op-rule)
  #:rules (replace value-balance lax-balance))

(check-equal? (consensus-param tweaked 'coinbase-maturity) 50)
(check-false (consensus-rule tweaked 'duplicate-inputs))
(check-equal? (diff-consensus ctv-rules tweaked)
              '((rule - duplicate-inputs)
                (rule + always-ok)
                (rule ~ value-balance)
                (param coinbase-maturity 100 -> 50)))

(test-case "bad changes are refused"
  (check-exn #rx"only an upgradable NOP"
             (λ () (define-consensus bad #:extends bitcoin #:opcodes (upgrade dup #:to ctv)) bad))
  (check-exn #rx"unknown opcode"
             (λ () (define-consensus bad #:extends bitcoin #:opcodes (upgrade nop5 #:to cat)) bad))
  (check-exn #rx"different byte"
             (λ () (define-consensus bad #:extends bitcoin #:opcodes (upgrade nop5 #:to ctv)) bad))
  (check-exn #rx"no such rule"
             (λ () (define-consensus bad #:extends bitcoin #:rules (remove no-such-rule)) bad))
  (check-exn #rx"no such parameter"
             (λ () (define-consensus bad #:extends bitcoin #:params (set no-such-param 1)) bad))
  (check-exn #rx"must have the name it replaces"
             (λ () (define-consensus bad #:extends bitcoin #:rules (replace value-balance no-op-rule)) bad))
  (check-exn #rx"already exists"
             (λ () (define-consensus bad #:extends bitcoin #:rules (add (rule 'value-balance 'tx "" void))) bad)))
