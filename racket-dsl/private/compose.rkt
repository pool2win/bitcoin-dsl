#lang racket/base
;; Composing consensus values: extend one with changes, compare two.
;;
;; A soft-fork proposal is a small change list over its parent: upgrade a
;; NOP to a new opcode, add or replace a rule, change a parameter, add a
;; sighash version. diff-consensus shows exactly what differs, and replay
;; uses that diff to tell which steps a target node can check.

(require racket/list
         racket/match
         "script.rkt"
         "values.rkt"
         "consensus.rkt")

(provide extend-consensus
         diff-consensus
         (struct-out opcode-change)
         register-opcode!
         known-opcode
         register-consensus!
         registered-consensus
         registered-consensus-names
         audit-lock)

;; Opcodes a consensus can upgrade to, by name (e.g. ctv from proposals.rkt).
(define known-opcodes (make-hasheq))

(define (register-opcode! oc) (hash-set! known-opcodes (opcode-name oc) oc))

(define (known-opcode name)
  (hash-ref known-opcodes name
            (λ () (raise-arguments-error 'define-consensus "unknown opcode; known ones can be upgraded to"
                                         "opcode" name "known" (sort (hash-keys known-opcodes) symbol<?)))))

;; Consensus values by name, for describe.
(define consensus-registry (make-hasheq))

(define (register-consensus! c) (hash-set! consensus-registry (consensus-name c) c) c)

(define (registered-consensus name) (hash-ref consensus-registry name #f))

(define (registered-consensus-names) (sort (hash-keys consensus-registry) symbol<?))

(void (register-consensus! bitcoin))

;; changes is a list of:
;;   (upgrade old new)          replace the upgradable NOP old with known opcode new
;;   (add-rule rule)            append a rule
;;   (remove-rule name)
;;   (replace-rule name rule)    rule must have the same name: new behaviour, same slot
;;   (set-param key value)
;;   (add-sighash version selector)
(define (extend-consensus parent name changes)
  (define who 'define-consensus)
  (define (check-rule-exists rules n)
    (unless (findf (λ (r) (eq? (rule-name r) n)) rules)
      (raise-arguments-error who "no such rule in the parent" "rule" n)))
  (define-values (rules opcodes sighash params)
    (for/fold ([rules (consensus-rules parent)]
               [opcodes (consensus-opcodes parent)]
               [sighash (consensus-sighash parent)]
               [params (consensus-params parent)])
              ([ch (in-list changes)])
      (match ch
        [(list 'upgrade old new)
         (define b (opcode-byte-of old))
         (define current (and b (hash-ref opcodes b #f)))
         (unless (and current (eq? (opcode-kind current) 'nop))
           (raise-arguments-error who "only an upgradable NOP can be upgraded" "opcode" old))
         (define oc (known-opcode new))
         (unless (= (opcode-byte oc) b)
           (raise-arguments-error who "the new opcode lives at a different byte" "old" old "new" new))
         (values rules (hash-set opcodes b oc) sighash params)]
        [(list 'add-rule r)
         (when (findf (λ (x) (eq? (rule-name x) (rule-name r))) rules)
           (raise-arguments-error who "a rule with this name already exists; use replace" "rule" (rule-name r)))
         (values (append rules (list r)) opcodes sighash params)]
        [(list 'remove-rule n)
         (check-rule-exists rules n)
         (values (filter (λ (r) (not (eq? (rule-name r) n))) rules) opcodes sighash params)]
        [(list 'replace-rule n r)
         (check-rule-exists rules n)
         (unless (eq? (rule-name r) n)
           (raise-arguments-error who "a replacement rule must have the name it replaces"
                                  "replacing" n "given" (rule-name r)))
         (values (map (λ (x) (if (eq? (rule-name x) n) r x)) rules) opcodes sighash params)]
        [(list 'set-param k v)
         (unless (hash-has-key? params k) (raise-arguments-error who "no such parameter" "param" k))
         (values rules opcodes sighash (hash-set params k v))]
        [(list 'add-sighash version selector)
         (values rules opcodes (hash-set sighash version selector) params)])))
  (register-consensus! (consensus name parent rules opcodes sighash params)))

;; An opcode slot that differs; from and to are opcode names or #f.
(struct opcode-change (byte from to)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc c port mode)
     (fprintf port "(opcode #x~a ~a -> ~a)" (number->string (opcode-change-byte c) 16)
              (or (opcode-change-from c) '-) (or (opcode-change-to c) '-)))])

;; What changes from a to b: opcode slots, rules (+ added, - removed,
;; ~ replaced), parameters and sighash versions.
(define (diff-consensus a b)
  (define (names oc) (and oc (opcode-name oc)))
  (define ao (consensus-opcodes a))
  (define bo (consensus-opcodes b))
  (define rule-names (λ (c) (map rule-name (consensus-rules c))))
  (append
   (for/list ([byte (in-list (sort (remove-duplicates (append (hash-keys ao) (hash-keys bo))) <))]
              #:unless (eq? (hash-ref ao byte #f) (hash-ref bo byte #f)))
     (opcode-change byte (names (hash-ref ao byte #f)) (names (hash-ref bo byte #f))))
   (for/list ([n (in-list (rule-names a))] #:unless (consensus-rule b n)) (list 'rule '- n))
   (for/list ([n (in-list (rule-names b))] #:unless (consensus-rule a n)) (list 'rule '+ n))
   (for/list ([n (in-list (rule-names a))]
              #:when (consensus-rule b n)
              #:unless (eq? (consensus-rule a n) (consensus-rule b n)))
     (list 'rule '~ n))
   (for/list ([k (in-list (sort (remove-duplicates (append (hash-keys (consensus-params a))
                                                           (hash-keys (consensus-params b))))
                                symbol<?))]
              #:unless (equal? (hash-ref (consensus-params a) k #f) (hash-ref (consensus-params b) k #f)))
     (list 'param k (hash-ref (consensus-params a) k #f) '-> (hash-ref (consensus-params b) k #f)))
   (for/list ([v (in-list (sort (remove-duplicates (append (hash-keys (consensus-sighash a))
                                                           (hash-keys (consensus-sighash b))))
                                symbol<?))]
              #:unless (eq? (hash-ref (consensus-sighash a) v #f) (hash-ref (consensus-sighash b) v #f)))
     (list 'sighash (cond [(not (hash-ref (consensus-sighash a) v #f)) '+]
                          [(not (hash-ref (consensus-sighash b) v #f)) '-]
                          [else '~])
           v))))

;; Audit

;; Where a lock's scripts are not enforced as written under consensus c:
;; an opcode that runs as an upgradable NOP there (e.g. ctv on a chain
;; without CTV), an opcode the chain does not define, or an OP_SUCCESS
;; byte in tapscript (which the model does not handle). '() when clean.
(define (audit-lock l c chain)
  (remove-duplicates
   (for*/list ([sc (in-list (lock-scripts l))]
               [op (in-list (car sc))]
               #:unless (pair? op)
               [w (in-value (audit-op op c chain (cdr sc)))]
               #:when w)
     w)))

(define (audit-op op c chain tapscript?)
  (define b (opcode-byte-of op))
  (define oc (and b (hash-ref (consensus-opcodes c) b #f)))
  (cond
    [(not oc) (list 'warning '#:opcode-undefined op '#:chain chain)]
    [(and tapscript? (op-success-byte? b)) (list 'warning '#:unsupported-op-success op '#:chain chain)]
    [(and (eq? (opcode-kind oc) 'nop) (not (eq? (opcode-name oc) op)))
     (list 'warning '#:rule-unenforced op '#:chain chain '#:runs-as (opcode-name oc))]
    [else #f]))
