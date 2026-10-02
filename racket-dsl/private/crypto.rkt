#lang racket/base
;; Symbolic crypto. Keys and secrets are names, a hash is a structured value
;; recording what was hashed, and a signature carries the exact list of
;; fields it commits to, so verification recomputes that list and compares.

(provide (struct-out key)
         (struct-out secret)
         (struct-out hashed)
         hash160
         sha256-of
         (struct-out sig)
         sighash-flags)

(struct key (name)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc k port mode) (write (key-name k) port))])

;; A hash preimage, revealed in a witness with #:reveal.
(struct secret (name)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc s port mode) (write (secret-name s) port))])

(struct hashed (fn value)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc h port mode)
     (fprintf port "(~a ~s)" (hashed-fn h) (hashed-value h)))])

(define (hash160 v) (hashed 'hash160 v))

(define (sha256-of v) (hashed 'sha256 v))

;; type is the sighash flag list, e.g. '(all); fields is the commitment,
;; an association list of (field-name . value) chosen by the consensus
;; value's sighash selector for this spend version.
(struct sig (key type fields)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc s port mode)
     (fprintf port "(sig ~s ~s)" (sig-key s) (sig-type s)))])

;; Normalises a sighash type to (base) or (base anyonecanpay), where base
;; is all, none or single. Accepts a single symbol or a list in any order.
(define (sighash-flags type)
  (define flags (if (list? type) type (list type)))
  (define bases (filter (λ (f) (memq f '(all none single))) flags))
  (unless (and (= (length bases) 1)
               (andmap (λ (f) (memq f '(all none single anyonecanpay))) flags)
               (<= (length (filter (λ (f) (eq? f 'anyonecanpay)) flags)) 1))
    (raise-argument-error 'sighash "one of all, none or single, optionally with anyonecanpay" type))
  (if (memq 'anyonecanpay flags) (list (car bases) 'anyonecanpay) bases))
