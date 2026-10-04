#lang racket/base
;; Documentation checks.
;;
;; 1. The generated reference pages match the describe registry. If this
;;    fails, run from the repository root:  racket docs/gen-reference.rkt
;; 2. Every page follows the ASD-STE100 rules that can be checked by
;;    machine (see AGENT.md): sentence length, unapproved words, words
;;    that end in -ing, phrasal verbs and contractions. Code, inline code
;;    and link targets are technical names and are not checked.

(require rackunit
         racket/file
         racket/list
         racket/string
         racket/path
         racket/runtime-path
         "../docs/gen-reference.rkt")

(define-runtime-path docs-dir* "../docs")
(define docs-dir (simplify-path docs-dir*))
(define reference-dir (build-path docs-dir "reference"))

(for ([p (in-list (reference-pages))])
  (check-equal? (file->string (build-path reference-dir (car p))) (cdr p)
                (format "docs/reference/~a is stale: run racket docs/gen-reference.rkt" (car p))))

;; STE

(define max-descriptive 25)
(define max-procedural 20)

(define unapproved
  '("allow" "allows" "allowed" "enable" "enables" "enabled" "ensure" "ensures" "verify" "verifies"
    "provide" "provides" "provided" "supply" "require" "requires" "required" "obtain" "obtains"
    "perform" "performs" "display" "displays" "indicate" "indicates" "determine" "determines"
    "locate" "additional" "approximately" "various" "whether" "via" "utilize" "simply" "just"
    "sufficient" "therefore" "e.g." "i.e." "etc."))

(define phrasal-verbs
  '("set up" "sets up" "look up" "looks up" "find out" "go back" "goes back" "carry out"
    "come back" "comes back" "pick up" "fill in" "check out" "turn on" "turn off" "point at"))

;; Words that end in -ing but are not -ing forms of verbs: approved nouns
;; ("warning" is the STE notice), prepositions, and the Bitcoin technical
;; name "halving".
(define ing-ok '("during" "string" "strings" "thing" "things" "nothing" "something" "anything" "everything"
                 "bring" "ping" "ring" "spring" "warning" "warnings" "halving"))

;; Prose of a page: no front matter, code blocks, inline code, comments,
;; link targets or snippet lines.
(define (prose text)
  (let* ([t (regexp-replace* #px"(?s:```.*?```)" text "")]
         [t (regexp-replace* #px"(?s:<!--.*?-->)" t "")]
         [t (regexp-replace* #px"`[^`]*`" t "CODE")]
         [t (regexp-replace* #px"\\]\\([^)]*\\)" t "]")]
         [t (regexp-replace* #px"https?://\\S+" t "URL")])
    t))

;; (kind . sentence) for every sentence. kind is step for numbered list
;; items (procedures), else text. Table cells and list items are separate units.
(define (sentences text)
  (append*
   (for/list ([line (in-list (string-split (prose text) "\n"))])
     (define trimmed (string-trim line))
     (define kind (if (regexp-match? #px"^\\d+\\. " trimmed) 'step 'text))
     (define units (if (string-prefix? trimmed "|") (string-split trimmed "|") (list trimmed)))
     (for*/list ([u (in-list units)]
                 [s (in-list (regexp-split #px"(?<=[.!?:;])\\s+" u))]
                 #:unless (regexp-match? #px"^[\\s#>*|:-]*$" s))
       (cons kind s)))))

(define (words s) (regexp-match* #px"[A-Za-z][A-Za-z'.-]*" s))

(define (problems s kind)
  (define ws (map string-downcase (words s)))
  (define lower (string-downcase s))
  (append
   (if (> (length ws) (if (eq? kind 'step) max-procedural max-descriptive))
       (list (format "~a words" (length ws))) '())
   (for/list ([w (in-list ws)] #:when (member (regexp-replace #px"[.]$" w (λ (x) (if (member w '("e.g." "i.e." "etc.")) x ""))) unapproved))
     (format "unapproved word \"~a\"" w))
   (for/list ([p (in-list phrasal-verbs)] #:when (regexp-match? (pregexp (string-append "\\b" p "\\b")) lower))
     (format "phrasal verb \"~a\"" p))
   (for/list ([w (in-list ws)] #:when (regexp-match? #px"n't$|'re$|'ve$|'ll$|'m$|^it's$" w))
     (format "contraction \"~a\"" w))
   (for/list ([w (in-list ws)]
              #:when (and (regexp-match? #px"^[a-z]{3,}ing$" w) (not (member w ing-ok))))
     (format "-ing word \"~a\"" w))))

;; The pages of the site and the README. The design notes in docs/design
;; are working notes and do not follow the standard.
(define-runtime-path readme "../README.md")
(define pages
  (cons (simplify-path readme)
        (for/list ([f (in-directory docs-dir (λ (d) (not (regexp-match? #px"/design$" (path->string d)))))]
                   #:when (regexp-match? #px"\\.md$" (path->string f)))
          f)))

(define report
  (append*
   (for/list ([f (in-list pages)])
     (for*/list ([ks (in-list (sentences (file->string f)))]
                 [p (in-value (problems (cdr ks) (car ks)))]
                 #:when (pair? p))
       (format "~a: ~a\n    ~a" (find-relative-path (simplify-path (build-path docs-dir 'up)) f) (string-join p ", ") (cdr ks))))))

(module+ main
  (for-each displayln report)
  (printf "~a problems\n" (length report)))

(test-case "docs follow ASD-STE100 (the rules a machine can check)"
  (check-equal? (length report) 0 (string-join (take report (min 30 (length report))) "\n")))
