#lang racket/base
;; Result values the agent branches on. They print in keyword form, e.g.
;; (rejected #:chain btc #:rule coinbase-maturity #:input 0 #:need 100 ...).

(provide (struct-out accepted)
         (struct-out rejected)
         (struct-out unverified)
         result-detail)

(define (write-keywords port head pairs)
  (write-string (format "(~a" head) port)
  (for ([p (in-list pairs)] #:when (cdr p))
    (fprintf port " #:~a ~s" (car p) (cdr p)))
  (write-string ")" port))

(struct accepted (chain tx step trace)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc r port mode)
     (write-keywords port 'accepted
                     (list (cons 'chain (accepted-chain r))
                           (cons 'tx (accepted-tx r))
                           (cons 'step (accepted-step r))
                           (cons 'trace (accepted-trace r)))))])

;; details is an association list of (name . value), specific to the rule.
(struct rejected (chain rule input details step trace)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc r port mode)
     (write-keywords port 'rejected
                     (append (list (cons 'chain (rejected-chain r))
                                   (cons 'rule (rejected-rule r))
                                   (cons 'input (rejected-input r)))
                             (rejected-details r)
                             (list (cons 'step (rejected-step r))
                                   (cons 'trace (rejected-trace r))))))])

(struct unverified (reason)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc r port mode)
     (write-keywords port 'unverified (list (cons 'reason (unverified-reason r)))))])

(define (result-detail r name)
  (cond [(assq name (rejected-details r)) => cdr]
        [else #f]))
