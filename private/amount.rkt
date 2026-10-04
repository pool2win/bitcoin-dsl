#lang racket/base
;; Amounts are exact satoshi counts. (btc x) and (sats n) build them, and
;; they print as (btc x) so results read back as DSL code.

(require racket/string)

(provide (struct-out amount)
         btc
         sats
         amount-sum
         sats-per-btc)

(define sats-per-btc 100000000)

(struct amount (sats)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc a port mode)
     (fprintf port "(btc ~a)" (sats->btc-string (amount-sats a))))])

(define (sats->btc-string n)
  (define s (real->decimal-string (/ n sats-per-btc) 8))
  (string-trim (string-trim s "0" #:left? #f #:repeat? #t) "." #:left? #f))

;; Floats like 49.99 are not exact, so round to the nearest satoshi and
;; refuse anything that is genuinely finer than one.
(define (btc x)
  (unless (real? x) (raise-argument-error 'btc "real?" x))
  (define exact-sats (* (inexact->exact x) sats-per-btc))
  (define n (round exact-sats))
  (unless (< (abs (- exact-sats n)) 1/1000)
    (raise-arguments-error 'btc "amount is finer than one satoshi" "amount" x))
  (amount n))

(define (sats n)
  (unless (exact-integer? n) (raise-argument-error 'sats "exact-integer?" n))
  (amount n))

(define (amount-sum amounts)
  (amount (for/sum ([a (in-list amounts)]) (amount-sats a))))
