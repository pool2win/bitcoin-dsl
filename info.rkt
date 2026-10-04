#lang info

(define collection "bitcoin")
(define deps '("base"))
(define build-deps '("rackunit-lib"))
(define pkg-desc "A Bitcoin DSL for modelling chains, transactions and scripts")

;; The repository root is the package. Do not compile or test the old Ruby
;; DSL, the Python venv for the docs, or the built docs site.
(define compile-omit-paths '("obsolete-ruby-dsl" ".venv" "site"))
(define test-omit-paths '("obsolete-ruby-dsl" ".venv" "site" "docs"))
