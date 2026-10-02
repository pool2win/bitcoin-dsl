#lang racket/base
;; A small Script interpreter over symbolic values.
;;
;; The interpreter knows nothing about specific opcodes: it looks each one
;; up in the table it is given, which comes from the consensus value. A
;; script is a list of opcode names and (push v) items; the stack is a list
;; with the top first.

(provide (struct-out opcode)
         (struct-out script-failure)
         (struct-out script-ctx)
         run-script
         stack-true?)

;; exec : stack script-ctx -> (or/c stack script-failure)
(struct opcode (name byte doc exec))

;; rule names the opcode or rule that failed; details is an alist.
(struct script-failure (rule details) #:transparent)

;; check-sig : sig pubkey -> boolean, bound to the input being verified.
;; emit receives trace events.
(struct script-ctx (check-sig emit))

(define (stack-true? v)
  (not (or (eq? v #f) (eqv? v 0) (equal? v #""))))

(define (run-script opcodes script stack ctx)
  (let loop ([ops script] [stack stack])
    (cond
      [(null? ops) stack]
      [else
       (define op (car ops))
       (define next
         (cond
           [(and (pair? op) (eq? (car op) 'push)) (cons (cadr op) stack)]
           [(hash-ref opcodes op #f) => (λ (oc) ((opcode-exec oc) stack ctx))]
           [else (script-failure 'bad-opcode (list (cons 'opcode op)))]))
       ((script-ctx-emit ctx) (list 'op op stack next))
       (if (script-failure? next)
           next
           (loop (cdr ops) next))])))
