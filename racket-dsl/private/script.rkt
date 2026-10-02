#lang racket/base
;; A small Script interpreter over symbolic values.
;;
;; The interpreter knows nothing about specific opcodes except flow control:
;; it looks each one up in the table it is given, which comes from the
;; consensus value. A script is a list of opcode names and (push v) items;
;; the stack is a list with the top first. True and false are 1 and #"",
;; as in real Script.

(provide (struct-out opcode)
         (struct-out script-failure)
         (struct-out script-ctx)
         run-script
         stack-true?
         script-bool)

;; exec : stack script-ctx -> (or/c stack script-failure), or #f for the
;; flow-control opcodes, which the interpreter runs itself.
(struct opcode (name byte doc exec))

;; rule names the opcode or rule that failed; details is an alist.
(struct script-failure (rule details) #:transparent)

;; Hooks bound to the input being verified:
;;   check-sig      : sig pubkey -> boolean
;;   check-sequence : n -> (or/c #f script-failure)   for CHECKSEQUENCEVERIFY
;;   check-locktime : n -> (or/c #f script-failure)   for CHECKLOCKTIMEVERIFY
;;   emit           : trace event -> void
(struct script-ctx (check-sig check-sequence check-locktime emit))

(define (stack-true? v)
  (not (or (eq? v #f) (eqv? v 0) (equal? v #""))))

(define (script-bool b) (if b 1 #""))

(define flow-ops '(if notif else endif))

(define (run-script opcodes script stack ctx)
  ;;* Walk the script with a stack of IF conditions; an op runs only when every enclosing condition holds.
  (let loop ([ops script] [stack stack] [conds '()])
    (cond
      [(null? ops)
       (if (null? conds) stack (script-failure 'unbalanced-conditional '()))]
      [else
       (define op (car ops))
       (define name (if (pair? op) 'push op))
       (define executing? (andmap values conds))
       ;;* Flow control updates the condition stack even in an untaken branch; other ops are skipped there.
       (define-values (next next-conds)
         (cond
           [(and (memq name flow-ops) (hash-ref opcodes name #f))
            (run-flow name stack conds executing?)]
           [(not executing?) (values stack conds)]
           [(eq? name 'push) (values (cons (cadr op) stack) conds)]
           [(hash-ref opcodes name #f) => (λ (oc) (values ((opcode-exec oc) stack ctx) conds))]
           [else (values (script-failure 'bad-opcode (list (cons 'opcode name))) conds)]))
       ;;* Trace every op that ran, with the stack before and after.
       (when (or executing? (memq name flow-ops))
         ((script-ctx-emit ctx) (list 'op op stack next)))
       (if (script-failure? next)
           next
           (loop (cdr ops) next next-conds))])))

(define (run-flow name stack conds executing?)
  (define (unbalanced) (values (script-failure 'unbalanced-conditional (list (cons 'opcode name))) conds))
  (case name
    [(if notif)
     (cond
       [(not executing?) (values stack (cons #f conds))]
       [(null? stack) (values (script-failure 'stack-underflow (list (cons 'opcode name))) conds)]
       [else
        (define c (stack-true? (car stack)))
        (values (cdr stack) (cons (if (eq? name 'if) c (not c)) conds))])]
    [(else) (if (null? conds) (unbalanced) (values stack (cons (not (car conds)) (cdr conds))))]
    [(endif) (if (null? conds) (unbalanced) (values stack (cdr conds)))]))
