#lang racket/base
;; Soft-fork proposals as values that define-consensus can upgrade to.
;;
;; CTV (BIP119): OP_CHECKTEMPLATEVERIFY on NOP4 (0xb3). A template commits
;; to the spending tx's version, locktime, input count, sequences, outputs
;; and the input's index; the opcode compares that commitment with the
;; spending tx. The commitment is an alist like a sighash commitment, so a
;; mismatch names the fields that differ. The model has no scriptSigs, so
;; BIP119's scriptSig hash never appears.

(require racket/list
         "amount.rkt"
         "crypto.rkt"
         "values.rkt"
         "script.rkt"
         "policy.rkt"
         "consensus.rkt"
         "compose.rkt")

(provide template
         (struct-out ctv-template)
         template-hash
         ctv-commitment
         tx-ctv-commitment
         ctv-opcode
         policy-ctv)

(define (output-value o) (list (txout-amount o) (lock->spk (txout-lock o))))

;; outputs are (amount spk) pairs, the encoding BIP143 commitments use.
(define (ctv-commitment version locktime sequences outputs index)
  (list (cons 'version version)
        (cons 'locktime locktime)
        (cons '(inputs count) (length sequences))
        (cons '(inputs sequences) sequences)
        (cons '(outputs all) outputs)
        (cons '(own-input index) index)))

(define (tx-ctv-commitment t index)
  (ctv-commitment (tx-version t) (tx-locktime t)
                  (map txin-sequence (tx-inputs t))
                  (map output-value (tx-outputs t))
                  index))

;; What a CTV-locked coin must be spent by. Defaults match what spend and
;; define-tx build: version 2, locktime 0, final sequences, input 0 of 1.
(struct ctv-template (version locktime sequences outputs index)
  #:transparent
  #:methods gen:custom-write
  [(define (write-proc t port mode)
     (fprintf port "(template #:outputs ~s~a)"
              (for/list ([o (in-list (ctv-template-outputs t))])
                (list (txout-label o) (txout-lock o) (txout-amount o)))
              (if (= (length (ctv-template-sequences t)) 1)
                  ""
                  (format " #:inputs ~a" (length (ctv-template-sequences t))))))])

(define (template #:outputs outputs
                  #:version [version 2]
                  #:locktime [locktime 0]
                  #:inputs [inputs 1]
                  #:sequences [sequences (make-list inputs #xffffffff)]
                  #:index [index 0])
  (unless (and (list? outputs) (andmap txout? outputs))
    (raise-argument-error 'template "(listof output)" outputs))
  (unless (< -1 index (length sequences))
    (raise-arguments-error 'template "index is not an input of the template" "index" index))
  (ctv-template version locktime sequences outputs index))

(define (template-commitment t)
  (ctv-commitment (ctv-template-version t) (ctv-template-locktime t)
                  (ctv-template-sequences t)
                  (map output-value (ctv-template-outputs t))
                  (ctv-template-index t)))

(define (template-hash t) (hashed 'ctv (template-commitment t)))

;; BIP119. A template hash is compared with the spending tx; 32-byte
;; arguments other than a model template hash cannot be checked
;; symbolically; any other size is a NOP, left for future upgrades.
(define (op-ctv s ctx)
  (cond
    [(null? s) (script-failure 'stack-underflow (list (cons 'opcode 'ctv)))]
    [else
     (define arg (car s))
     (cond
       [(and (hashed? arg) (eq? (hashed-fn arg) 'ctv))
        (define now (tx-ctv-commitment (script-ctx-tx ctx) (script-ctx-index ctx)))
        (if (equal? (hashed-value arg) now)
            s
            (let ([fields (field-diff (hashed-value arg) now)])
              (script-failure 'ctv-template-mismatch
                              (list (cons 'fields fields)
                                    (cons 'expected (for/list ([f (in-list fields)]) (assoc f (hashed-value arg))))
                                    (cons 'got (for/list ([f (in-list fields)]) (assoc f now)))))))]
       [(and (bytes? arg) (= (bytes-length arg) 32))
        (script-failure 'unsupported (list (cons 'feature 'ctv-raw-hash)))]
       [else s])]))

(define ctv-opcode
  (make-opcode 'ctv #xb3
               "BIP119 CHECKTEMPLATEVERIFY: fail if the tx that spends the coin does not agree with the template hash on top of the stack."
               op-ctv
               #:failures (hash 'ctv-template-mismatch
                                "The tx that spends the coin does not agree with the CTV template. #:fields gives the fields that are different. #:expected and #:got give the values of the template and of the tx.")))

(register-opcode! ctv-opcode)

;; The (ctv t) policy fragment: the template's hash, and the sequence and
;; locktime it fixes so #:path sets them.
(define (policy-ctv t)
  (unless (ctv-template? t) (raise-argument-error 'ctv "template?" t))
  (define seq (list-ref (ctv-template-sequences t) (ctv-template-index t)))
  (define lt (ctv-template-locktime t))
  ;; With a locktime, build-tx would otherwise make a final sequence
  ;; non-final, so pin the template's sequence whenever either is set.
  (p-ctv (template-hash t) t
         (and (or (not (= seq #xffffffff)) (positive? lt)) seq)
         (and (positive? lt) lt)))
