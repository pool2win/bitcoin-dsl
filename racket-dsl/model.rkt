#lang racket/base
;; #lang bitcoin/model: all of Racket plus the modelling forms.

(require (for-syntax racket/base syntax/parse)
         racket
         "private/amount.rkt"
         "private/crypto.rkt"
         "private/policy.rkt"
         "private/values.rkt"
         "private/result.rkt"
         "private/consensus.rkt"
         "private/session.rkt"
         "private/inspect.rkt"
         "private/compose.rkt"
         "private/proposals.rkt"
         "private/describe.rkt")

(provide (all-from-out racket)
         ;; definition forms
         chain
         keys
         define-tx
         contract
         define-consensus
         ;; values
         btc
         sats
         amount?
         key?
         coin?
         tx?
         wpkh
         tr
         hash160
         secret
         branch-name
         branch-needs
         input
         output
         output-of
         out
         ;; consensus
         bitcoin
         diff-consensus
         template
         ;; session
         mine
         spend
         add-input
         try
         broadcast
         confirm
         confirmed?
         height
         utxos
         fee
         branches
         last-trace
         explain
         trace-events
         snapshot
         restore
         ;; sighash queries
         sig-of
         commits
         free-fields
         mutate
         edit
         intact?
         breaks-entries
         audit
         scenario-log
         describe
         reset-session!
         ;; results
         accepted?
         rejected?
         rejected-rule
         rejected-chain
         rejected-input
         result-detail)

;; (chain btc #:rules bitcoin) binds btc to a fresh chain.
(define-syntax (chain stx)
  (syntax-parse stx
    [(_ name:id #:rules rules:expr)
     #'(define name (make-chain! 'name rules))]))

;; (keys alice bob) binds each name to the key of that name.
(define-syntax (keys stx)
  (syntax-parse stx
    [(_ name:id ...)
     #'(begin (define name (key 'name)) ...)]))

;; Defines the tx and binds each output label to that output's coin:
;;   (define-tx pay
;;     #:inputs  ([cb #:sign alice])
;;     #:outputs ([to-bob (wpkh bob) (btc 49.99)]))
;; binds pay and to-bob = (output-of pay 0).
(define-syntax (define-tx stx)
  (syntax-parse stx
    [(_ name:id
        #:inputs ([in-coin:expr in-opt ...] ...)
        #:outputs ([label:id lock:expr amt:expr] ...)
        tx-opt ...)
     (with-syntax ([(idx ...) (for/list ([i (in-range (length (syntax->list #'(label ...))))]) i)])
       #'(begin
           (define name
             (build-tx 'name
                       (list (input in-coin in-opt ...) ...)
                       (list (output 'label lock amt) ...)
                       tx-opt ...))
           (define label (output-of name idx)) ...))]))

;; (contract htlc (sender receiver secret timeout)
;;   (or [claim  (and (pk receiver) (sha256 secret))]
;;       [refund (and (pk sender) (older timeout))]))
;; defines htlc as a function from its parameters to a P2WSH lock. An or
;; arm may be labelled; the label names the spend path in branches and
;; #:path. Unlabelled arms are named by position.
(define-syntax (contract stx)
  (syntax-parse stx
    [(_ name:id (param:id ...) body)
     #'(define (name param ...)
         (wsh (make-contract-instance 'name (list param ...) (policy body))))]))

(begin-for-syntax
  (define policy-ops '(pk sha256 older after and or thresh ctv)))

(define-syntax (policy stx)
  (syntax-parse stx
    #:datum-literals (pk sha256 older after and or thresh ctv)
    [(_ (pk e:expr)) #'(policy-pk e)]
    [(_ (ctv e:expr)) #'(policy-ctv e)]
    [(_ (sha256 e:expr)) #'(policy-sha256 e)]
    [(_ (older e:expr)) #'(policy-older e)]
    [(_ (after e:expr)) #'(policy-after e)]
    [(_ (and p ...+)) #'(policy-and (list (policy p) ...))]
    [(_ (or arm ...+)) #'(policy-or (list (policy-arm arm) ...))]
    [(_ (thresh k:expr p ...+)) #'(policy-thresh k (list (policy p) ...))]
    [(_ other)
     (raise-syntax-error 'contract
                         "not a policy form; expected pk, sha256, older, after, and, or, thresh or ctv"
                         #'other)]))

(define-syntax (policy-arm stx)
  (syntax-parse stx
    [(_ (label:id p))
     #:when (not (memq (syntax-e #'label) policy-ops))
     #'(cons 'label (policy p))]
    [(_ p) #'(cons #f (policy p))]))

;; (define-consensus ctv-rules #:extends bitcoin
;;   #:opcodes (upgrade nop4 #:to ctv)
;;   #:rules   (add r) (remove name) (replace name r)
;;   #:params  (set coinbase-maturity 50)
;;   #:sighash (add version selector))
;; binds ctv-rules to bitcoin with those changes. Opcode names are not
;; evaluated: they name a NOP slot and a known proposal opcode.
(begin-for-syntax
  (define-syntax-class opcode-change
    #:datum-literals (upgrade)
    (pattern (upgrade old:id #:to new:id) #:with change #'(list 'upgrade 'old 'new)))
  (define-syntax-class rule-change
    #:datum-literals (add remove replace)
    (pattern (add r:expr) #:with change #'(list 'add-rule r))
    (pattern (remove n:id) #:with change #'(list 'remove-rule 'n))
    (pattern (replace n:id r:expr) #:with change #'(list 'replace-rule 'n r)))
  (define-syntax-class param-change
    #:datum-literals (set)
    (pattern (set k:id v:expr) #:with change #'(list 'set-param 'k v)))
  (define-syntax-class sighash-change
    #:datum-literals (add)
    (pattern (add v:id sel:expr) #:with change #'(list 'add-sighash 'v sel))))

(define-syntax (define-consensus stx)
  (syntax-parse stx
    [(_ name:id #:extends parent:expr
        (~alt (~seq #:opcodes o:opcode-change ...+)
              (~seq #:rules r:rule-change ...+)
              (~seq #:params p:param-change ...+)
              (~seq #:sighash s:sighash-change ...+))
        ...)
     #'(define name
         (extend-consensus parent 'name
                           (list o.change ... ... r.change ... ... p.change ... ... s.change ... ...)))]))
