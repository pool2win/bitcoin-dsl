#lang bitcoin/model
;; CTV: the same vault on a chain with CTV and one without.

(require rackunit)

(define-consensus ctv-rules #:extends bitcoin
  #:opcodes (upgrade nop4 #:to ctv))

(chain mainnet #:rules bitcoin)
(chain signet #:rules ctv-rules)
(keys alice cold mallory)

(define tmpl (template #:outputs (list (output 'to-cold (wpkh cold) (btc 49.98)))))
(contract vault () (ctv tmpl))

;; A confirmed vault coin on ch.
(define (vaulted-on ch)
  (define cb (first (mine 1 #:on ch #:to alice)))
  (void (mine 100 #:on ch))
  (define lock (spend cb #:sign alice #:outputs (list (output 'vaulted (vault) (btc 49.99)))))
  (check-pred accepted? (confirm lock))
  (out lock 'vaulted))

(define v-main (vaulted-on mainnet))
(define v-sig (vaulted-on signet))

(define (honest c) (spend c #:outputs (list (output 'to-cold (wpkh cold) (btc 49.98)))))
(define (thief c) (spend c #:outputs (list (output 'stolen (wpkh mallory) (btc 49.98)))))

(test-case "branches show the template"
  (check-equal? (map branch-needs (branches v-sig)) `(((template ,tmpl)))))

(test-case "honest spends are accepted on both chains"
  (check-pred accepted? (try (honest v-main)))
  (check-pred accepted? (try (honest v-sig))))

(test-case "the covenant is enforced only where CTV exists"
  (check-pred accepted? (try (thief v-main)))
  (define r (try (thief v-sig)))
  (check-equal? (rejected-rule r) 'ctv-template-mismatch)
  (check-equal? (rejected-chain r) 'signet)
  (check-equal? (result-detail r 'fields) '((outputs all)))
  ;; The mismatch shows the template's value and the tx's.
  (check-equal? (map car (result-detail r 'expected)) '((outputs all)))
  (check-equal? (cadr (assoc '(outputs all) (result-detail r 'got)))
                (list (btc 49.98) `(v0 ,(hash160 mallory)))))

(test-case "explain shows ctv running as nop4 on mainnet"
  (check-pred accepted? (try (thief v-main)))
  (check-not-false (member '(op ctv #:as nop4) (map (λ (e) (take e (min 4 (length e)))) (explain (last-trace))))))

(test-case "the template also fixes version, sequences and fee"
  (check-equal? (result-detail (try (spend v-sig #:sequence #xfffffffe #:outputs (list (output 'to-cold (wpkh cold) (btc 49.98)))))
                               'fields)
                '((inputs sequences)))
  (check-equal? (result-detail (try (spend v-sig #:outputs (list (output 'to-cold (wpkh cold) (btc 49.97))))) 'fields)
                '((outputs all))))

(test-case "audit warns only where the covenant is unenforced"
  (check-equal? (audit (vault) #:on mainnet) '((warning #:rule-unenforced ctv #:chain mainnet #:runs-as nop4)))
  (check-equal? (audit (vault) #:on signet) '())
  (check-equal? (audit (wpkh alice) #:on mainnet) '()))

(test-case "a template with a locktime pins the sequence"
  (define t2 (template #:locktime 5 #:outputs (list (output 'o (wpkh cold) (btc 49.98)))))
  (contract later () (ctv t2))
  (define cb (first (mine 1 #:on signet #:to alice)))
  (void (mine 100 #:on signet))
  (define lock (spend cb #:sign alice #:outputs (list (output 'l (later) (btc 49.99)))))
  (check-pred accepted? (confirm lock))
  (check-pred accepted? (try (spend (out lock 'l) #:outputs (list (output 'o (wpkh cold) (btc 49.98)))))))

(test-case "spend can name its tx"
  (check-true (string-prefix? (format "~s" (spend v-sig #:name 'sweep #:outputs (list (output 'o (wpkh cold) (btc 49.98)))))
                              "#<tx sweep ")))
