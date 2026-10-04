#lang bitcoin/model
;; BIP143 sighash flags: free-fields agrees with verification.
;;
;; For every flag combination, an edit that free-fields calls free must
;; leave the tx valid, and an edit it does not must be rejected. This is
;; the model-side half of the conformance sighash matrix.

(require rackunit)

(chain mainnet #:rules bitcoin)
(keys alice bob carol nobody)

(define ca (first (mine 1 #:on mainnet #:to alice)))
(define cb (first (mine 1 #:on mainnet #:to bob)))
(mine 100 #:on mainnet)

;; Two inputs signed with the same flags, two outputs.
(define (signed-with flags)
  (spend (list (input ca #:sign alice #:sighash flags)
               (input cb #:sign bob #:sighash flags))
         #:outputs (list (output 'a (wpkh carol) (btc 30))
                         (output 'b (wpkh carol) (btc 69.9)))))

;; Edits that keep the tx valid apart from signatures:
;; (name-in-free-fields edit-path value).
(define value-edits
  `(((output a amount) (output 0 amount) ,(btc 29.9))
    ((output a lock)   (output 0 lock)   ,(wpkh nobody))
    ((output b amount) (output 1 amount) ,(btc 69.8))
    ((output b lock)   (output 1 lock)   ,(wpkh nobody))
    ((input 0 sequence) (input 0 sequence) #xfffffffe)
    ((input 1 sequence) (input 1 sequence) #xfffffffe)
    (version  version  1)
    (locktime locktime 1)))

(define flag-sets
  '((all) (all anyonecanpay) (none) (none anyonecanpay) (single) (single anyonecanpay)))

(for ([flags (in-list flag-sets)])
  (define t (signed-with flags))
  (check-pred accepted? (try t) (format "~a: unedited tx" flags))
  (define free (free-fields t))
  (for ([e (in-list value-edits)])
    (define r (try (edit t (second e) (third e))))
    (check-equal? (accepted? r) (and (member (first e) free) #t)
                  (format "~a: ~a free=~a result=~a" flags (first e) (member (first e) free) r))))

(define expected-free
  `(((all) . ())
    ((all anyonecanpay) . ((inputs append) (inputs remove-others)))
    ((none) . ((outputs append)
               (output a amount) (output a lock) (output b amount) (output b lock)))
    ((none anyonecanpay) . ((inputs append) (inputs remove-others) (outputs append)
                            (output a amount) (output a lock) (output b amount) (output b lock)))
    ((single) . ((outputs append)))
    ;; Alone, bob's input moves to index 0 and would commit to output a.
    ((single anyonecanpay) . ((inputs append) (outputs append)))))

(for ([e (in-list expected-free)])
  (check-equal? (free-fields (signed-with (car e))) (cdr e) (format "~a" (car e))))

(test-case "SINGLE with no output at the input's index commits to no outputs (BIP143)"
  (define t (spend (list (input ca #:sign alice #:sighash 'single)
                         (input cb #:sign bob #:sighash 'single))
                   #:outputs (list (output 'a (wpkh carol) (btc 99.9)))))
  (check-pred accepted? (try t))
  (check-equal? (commits (sig-of t 1))
                '(version (inputs outpoints)
                  (own-input outpoint) (own-prevout script) (own-prevout amount) (own-input sequence)
                  locktime))
  (check-equal? (breaks-entries (mutate t '(output a amount) (btc 99)))
                `((sig ,alice 0 #:fields ((own-output))))))

(test-case "sighash flags are normalised and validated"
  (check-equal? (commits (sig-of (spend ca #:sign alice #:sighash '(anyonecanpay none)
                                        #:outputs (list (output 'a (wpkh carol) (btc 49))))
                                 0))
                '(version (own-input outpoint) (own-prevout script) (own-prevout amount)
                  (own-input sequence) locktime))
  (check-exn #rx"one of all, none or single"
             (λ () (input ca #:sign alice #:sighash '(all none)))))
