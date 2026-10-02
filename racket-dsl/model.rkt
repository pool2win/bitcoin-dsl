#lang racket/base
;; #lang bitcoin/model: all of Racket plus the modelling forms.

(require (for-syntax racket/base syntax/parse)
         racket
         "private/amount.rkt"
         "private/values.rkt"
         "private/result.rkt"
         "private/consensus.rkt"
         "private/session.rkt")

(provide (all-from-out racket)
         ;; definition forms
         chain
         keys
         define-tx
         ;; values
         btc
         sats
         amount?
         key?
         coin?
         tx?
         wpkh
         hash160
         input
         output
         output-of
         out
         ;; consensus
         bitcoin
         ;; session
         mine
         spend
         try
         broadcast
         confirm
         confirmed?
         utxos
         fee
         last-trace
         scenario-log
         reset-session!
         ;; results
         accepted?
         rejected?
         rejected-rule
         rejected-input
         result-detail)

;; (chain btc #:rules bitcoin) binds btc to a fresh chain.
(define-syntax (chain stx)
  (syntax-parse stx
    [(_ name:id #:rules rules:expr)
     #'(define name (make-chain! 'name rules))]))

;; (keys alice bob) binds each name to the key of that name.
(define-syntax (keys stx)
  (syntax-parse stx
    [(_ name:id ...)
     #'(begin (define name (key 'name)) ...)]))

;; Defines the tx and binds each output label to that output's coin:
;;   (define-tx pay
;;     #:inputs  ([cb #:sign alice])
;;     #:outputs ([to-bob (wpkh bob) (btc 49.99)]))
;; binds pay and to-bob = (output-of pay 0).
(define-syntax (define-tx stx)
  (syntax-parse stx
    [(_ name:id
        #:inputs ([in-coin:expr in-opt ...] ...)
        #:outputs ([label:id lock:expr amt:expr] ...)
        tx-opt ...)
     (with-syntax ([(idx ...) (for/list ([i (in-range (length (syntax->list #'(label ...))))]) i)])
       #'(begin
           (define name
             (build-tx 'name
                       (list (input in-coin in-opt ...) ...)
                       (list (output 'label lock amt) ...)
                       tx-opt ...))
           (define label (output-of name idx)) ...))]))
