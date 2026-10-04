#lang racket/base
;; The generated reference pages match the describe registry. If this
;; fails, run from racket-dsl/:  racket docs/gen-reference.rkt

(require rackunit
         racket/file
         racket/runtime-path
         "../docs/gen-reference.rkt")

(define-runtime-path reference-dir "../docs/reference")

(for ([p (in-list (reference-pages))])
  (check-equal? (file->string (build-path reference-dir (car p))) (cdr p)
                (format "docs/reference/~a is stale: run racket docs/gen-reference.rkt" (car p))))
