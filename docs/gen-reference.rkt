#lang racket/base
;; Generates docs/reference/{forms,rules,opcodes}.md from the same describe
;; registry agents read over MCP, so the reference cannot drift from the
;; language. Run from the repository root:  racket docs/gen-reference.rkt
;; tests/docs.rkt fails when the generated files are out of date.

(require racket/list
         racket/string
         racket/runtime-path
         bitcoin/conform)

(provide reference-pages)

(define-runtime-path reference-dir "reference")

(define header "<!-- docs/gen-reference.rkt makes this page from the describe registry. Do not edit it. -->\n\n")

(define (escape s) (string-replace (string-replace s "|" "\\|") "\n" " "))

(define (forms-page)
  (define groups
    '((definition "Definition forms" "These forms bind names: chains, keys, contracts, transactions and rule sets.")
      (value "Values" "These forms make amounts, locks, inputs, outputs and transactions.")
      (consensus "Consensus" "These forms make, compare and audit rule sets.")
      (session "Session" "These forms change or test the state of the chains.")
      (query "Queries" "These forms read the state and return data.")
      (conformance "Conformance" "These forms replay a session against real nodes (`#lang bitcoin/conform`).")))
  (string-append
   header
   "# Forms\n\n"
   "This page lists each form that the language exports for agents, in the groups of `(describe)`. "
   "Over MCP, `describe` with a form name returns the same usage and doc.\n\n"
   (string-append*
    (for/list ([g (in-list groups)])
      (string-append
       (format "## ~a\n\n~a\n\n" (second g) (third g))
       (string-append*
        (for/list ([f (in-list (describe (first g)))])
          (format "### `~a`\n\n```racket\n~a\n```\n\n~a\n\n" (first f) (second f) (third f)))))))))

(define (rules-page)
  (define entries (describe 'rules))
  (define-values (rules rest*) (splitf-at entries (λ (e) (memq '#:scope e))))
  (string-append
   header
   "# Consensus rules\n\n"
   "This page lists the rules of the `bitcoin` consensus value, in the order that validation runs them. "
   "The `#:rule` of a rejection is one of these names, or one of the script rules below.\n\n"
   "| Rule | Scope | Description |\n|---|---|---|\n"
   (string-append*
    (for/list ([r (in-list rules)])
      (format "| `~a` | ~a | ~a |\n" (first r) (third r) (escape (fourth r)))))
   "\n## Script rules\n\n"
   (escape (second (first rest*)))
   "\n\n| Rule | Description |\n|---|---|\n"
   (string-append*
    (for/list ([r (in-list (rest rest*))])
      (format "| `~a` | ~a |\n" (first r) (escape (second r)))))
   "\n## Proposal rules\n\n"
   "| Rule | Opcode | Description |\n|---|---|---|\n"
   (string-append*
    (for*/list ([name '(ctv)]
                [f (in-list (cadr (memq '#:failures (describe name))))])
      (format "| `~a` | `~a` | ~a |\n" (car f) name (escape (cdr f)))))))

(define (opcodes-page)
  (string-append
   header
   "# Opcodes\n\n"
   "The DSL identifies opcodes by their byte. Scripts use names. Aliases such as `cltv`/`nop2`, `csv`/`nop3` and "
   "`ctv`/`nop4` are names for the same byte. Each consensus value sets the function of each byte.\n\n"
   "## In `bitcoin`\n\n| Opcode | Byte | Description |\n|---|---|---|\n"
   (string-append*
    (for/list ([o (in-list (describe 'opcodes))])
      (format "| `~a` | `0x~a` | ~a |\n" (first o)
              (string-downcase (number->string (third o) 16)) (escape (fourth o)))))
   "\n## Proposal opcodes\n\n`define-consensus` can change an upgradable NOP to one of these opcodes.\n\n"
   "| Opcode | Byte | Description |\n|---|---|---|\n"
   (string-append*
    (for/list ([name '(ctv)])
      (define d (describe name))
      (format "| `~a` | `0x~a` | ~a |\n" name
              (string-downcase (number->string (cadr (memq '#:byte d)) 16))
              (escape (cadr (memq '#:proposal d))))))))

;; (filename . contents) for every generated page.
(define (reference-pages)
  (list (cons "forms.md" (forms-page))
        (cons "rules.md" (rules-page))
        (cons "opcodes.md" (opcodes-page))))

(module+ main
  (for ([p (in-list (reference-pages))])
    (call-with-output-file (build-path reference-dir (car p)) #:exists 'truncate
      (λ (out) (write-string (cdr p) out)))
    (printf "wrote docs/reference/~a\n" (car p))))
