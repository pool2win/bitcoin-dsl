#lang racket/base
;; A small Script interpreter over symbolic values.
;;
;; Opcodes are identified by byte. A script is a list of opcode names and
;; (push v) items; a global registry maps every name, aliases included, to
;; its byte, and the consensus value's table maps bytes to behaviour. So
;; the same script runs a byte's NOP on one chain and the upgraded opcode
;; (e.g. ctv on 0xb3) on another. The stack is a list with the top first.
;; True and false are 1 and #"", as in real Script.


(provide (struct-out opcode)
         make-opcode
         opcode-byte-of
         op-success-byte?
         (struct-out script-failure)
         (struct-out script-ctx)
         run-script
         stack-true?
         script-bool)

;; kind is op, flow (run by the interpreter itself, exec #f) or nop (an
;; upgradable no-op a soft fork may redefine). failures maps the failure
;; rules this opcode can report to their docs.
(struct opcode (name byte doc exec kind failures))

(define (make-opcode name byte doc exec #:kind [kind 'op] #:failures [failures (hash)])
  (opcode name byte doc exec kind failures))

;; Every opcode name the model knows, with aliases, by byte.
(define opcode-bytes
  (hash 'if #x63 'notif #x64 'else #x67 'endif #x68 'verify #x69
        'drop #x75 'dup #x76 'swap #x7c 'size #x82
        'equal #x87 'equalverify #x88 'add #x93
        'sha256 #xa8 'hash160 #xa9 'checksig #xac 'checksigverify #xad
        'nop1 #xb0
        'nop2 #xb1 'cltv #xb1
        'nop3 #xb2 'csv #xb2
        'nop4 #xb3 'ctv #xb3
        'nop5 #xb4 'nop6 #xb5 'nop7 #xb6 'nop8 #xb7 'nop9 #xb8 'nop10 #xb9))

(define (opcode-byte-of name) (hash-ref opcode-bytes name #f))

;; BIP342: bytes that make a tapscript succeed unconditionally (OP_SUCCESSx).
(define (op-success-byte? b)
  (or (memv b '(80 98 137 138 141 142))
      (<= 126 b 129) (<= 131 b 134) (<= 149 b 153) (<= 187 b 254)))

;; rule names the opcode or rule that failed; details is an alist.
(struct script-failure (rule details) #:transparent)

;; What an opcode can see while verifying one input:
;;   check-sig      : sig pubkey -> boolean or script-failure
;;   check-sequence : n -> (or/c #f script-failure)   for CHECKSEQUENCEVERIFY
;;   check-locktime : n -> (or/c #f script-failure)   for CHECKLOCKTIMEVERIFY
;;   emit           : trace event -> void
;;   tx, index, spent-coins : the spending tx, this input's index and the
;;                    coins every input spends, for opcodes that inspect
;;                    the transaction (CTV and later proposals)
(struct script-ctx (check-sig check-sequence check-locktime emit tx index spent-coins))

(define (stack-true? v)
  (not (or (eq? v #f) (eqv? v 0) (equal? v #""))))

(define (script-bool b) (if b 1 #""))

;; opcodes maps byte -> opcode.
(define (run-script opcodes script stack ctx)
  ;;* Walk the script with a stack of IF conditions; an op runs only when every enclosing condition holds.
  (let loop ([ops script] [stack stack] [conds '()])
    (cond
      [(null? ops)
       (if (null? conds) stack (script-failure 'unbalanced-conditional '()))]
      [else
       (define op (car ops))
       (define push? (pair? op))
       (define oc (and (not push?) (let ([b (opcode-byte-of op)]) (and b (hash-ref opcodes b #f)))))
       (define flow? (and oc (eq? (opcode-kind oc) 'flow)))
       (define executing? (andmap values conds))
       ;;* Flow control updates the condition stack even in an untaken branch; other ops are skipped there.
       (define-values (next next-conds)
         (cond
           [flow? (run-flow (opcode-name oc) stack conds executing?)]
           [(not executing?) (values stack conds)]
           [push? (values (cons (cadr op) stack) conds)]
           [oc (values ((opcode-exec oc) stack ctx) conds)]
           [else (values (script-failure 'bad-opcode (list (cons 'opcode op))) conds)]))
       ;;* Trace every op that ran, with the stack before and after and the opcode the chain ran for it.
       (when (or executing? flow?)
         ((script-ctx-emit ctx) (list 'op op stack next (and oc (opcode-name oc)) (and oc (opcode-byte oc)))))
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
