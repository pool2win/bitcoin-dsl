#lang racket/base
;; Scenario log events. Every session action that changes or tests chain
;; state appends one, carrying the model values a replay needs: the
;; consensus value, the exact txs, and what each mined block contained.
;; Step numbers in results are positions in this log, starting at 1.

(require "values.rkt"
         "consensus.rkt")

(provide (struct-out ev-chain)
         (struct-out ev-mine)
         (struct-out block-info)
         (struct-out ev-tx))

(struct ev-chain (name consensus)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc e port mode)
     (fprintf port "(chain ~a #:rules ~a)" (ev-chain-name e) (consensus-name (ev-chain-consensus e))))])

;; payee is the coinbase lock; blocks has one block-info per mined block.
(struct ev-mine (chain payee blocks)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc e port mode)
     (fprintf port "(mine ~a ~a #:to ~s)" (ev-mine-chain e) (length (ev-mine-blocks e)) (ev-mine-payee e)))])

;; coinbase is the model coinbase tx; included are the other txs in order.
(struct block-info (height coinbase included) #:transparent)

;; verb is try or broadcast; verdict is #f (accepted) or
;; (list rule input details) as returned by validate-tx. opcodes and rules
;; are the opcode bytes and rule names validation exercised, so replay can
;; tell whether a target that lacks some rule can check this step.
(struct ev-tx (verb chain tx verdict opcodes rules)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc e port mode)
     (fprintf port "(~a ~a ~s ~a)" (ev-tx-verb e) (ev-tx-chain e) (ev-tx-tx e)
              (if (ev-tx-verdict e) (format "(rejected ~a)" (car (ev-tx-verdict e))) "accepted")))])
