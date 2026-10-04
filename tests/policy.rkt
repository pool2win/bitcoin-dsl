#lang bitcoin/model
;; Contracts: compiled scripts, branch enumeration, and the rule each
;; kind of bad spend trips.

(require rackunit
         (only-in "../private/session.rkt" make-chain!))

(keys alice bob carol)

(contract htlc (sender receiver secret timeout)
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(define s (secret 's1))

;; A fresh chain with a confirmed coin of 49.99 BTC under lock.
(define (locked-coin chain-name lock)
  (define ch (make-chain! chain-name bitcoin))
  (define cb (first (mine 1 #:on ch #:to alice)))
  (mine 100 #:on ch)
  (define fund (spend cb #:sign alice #:outputs (list (output 'locked lock (btc 49.99)))))
  (check-pred accepted? (confirm fund))
  (values ch (out fund 'locked)))

(define (to-carol) (list (output 'paid (wpkh carol) (btc 49.98))))

(test-case "claim without the preimage fails the size check"
  (define-values (ch c) (locked-coin 'p1 (htlc alice bob s 144)))
  (define r (try (spend c #:path 'claim #:sign bob #:outputs (to-carol))))
  (check-equal? (rejected-rule r) 'equalverify))

(test-case "claim signed by the wrong key"
  (define-values (ch c) (locked-coin 'p2 (htlc alice bob s 144)))
  (define r (try (spend c #:path 'claim #:sign alice #:reveal s #:outputs (to-carol))))
  (check-equal? (rejected-rule r) 'checksigverify)
  (check-equal? (result-detail r 'cause) 'empty-signature))

(test-case "refund with relative locks disabled fails CSV in the script"
  (define-values (ch c) (locked-coin 'p3 (htlc alice bob s 144)))
  (mine 144 #:on ch)
  (define r (try (spend c #:path 'refund #:sign alice #:sequence #xffffffff #:outputs (to-carol))))
  (check-equal? (rejected-rule r) 'csv)
  (check-equal? (result-detail r 'reason) 'sequence-disabled))

(test-case "explain shows the IF branch taken"
  (define-values (ch c) (locked-coin 'p4 (htlc alice bob s 144)))
  (check-pred accepted? (try (spend c #:path 'claim #:sign bob #:reveal s #:outputs (to-carol))))
  (define ops (for/list ([e (explain (last-trace))] #:when (eq? (first e) 'op)) (second e)))
  (check-equal? (take ops 3) `(if (push ,bob) checksigverify))
  (check-not-false (member 'else ops)))

(contract any-of (a b c)
  (or (pk a) (pk b) (pk c)))

(test-case "unlabelled arms are named by position, and each one spends"
  (define-values (ch c) (locked-coin 'p5 (any-of alice bob carol)))
  (check-equal? (map branch-name (branches c)) '(|0| |1| |2|))
  (for ([path '(|0| |1| |2|)] [k (list alice bob carol)])
    (check-pred accepted? (try (spend c #:path path #:sign k #:outputs (to-carol))) (format "path ~a" path))))

(contract nested (a b c)
  (or [hot (or [first-key (pk a)] [second-key (pk b)])]
      [cold (pk c)]))

(test-case "nested labels join with a slash"
  (define-values (ch c) (locked-coin 'p6 (nested alice bob carol)))
  (check-equal? (map branch-name (branches c)) '(hot/first-key hot/second-key cold))
  (check-pred accepted? (try (spend c #:path 'hot/second-key #:sign bob #:outputs (to-carol))))
  (check-pred accepted? (try (spend c #:path 'cold #:sign carol #:outputs (to-carol)))))

(contract two-of-three (a b c)
  (thresh 2 (pk a) (pk b) (pk c)))

(test-case "thresh enumerates key combinations"
  (define-values (ch c) (locked-coin 'p7 (two-of-three alice bob carol)))
  (check-equal? (map branch-name (branches c)) '(alice+bob alice+carol bob+carol))
  (check-pred accepted? (try (spend c #:path 'alice+carol #:sign (list alice carol) #:outputs (to-carol))))
  (define r (try (spend c #:path 'alice+carol #:sign alice #:outputs (to-carol))))
  (check-equal? (rejected-rule r) 'eval-false))

(contract after-height (a h)
  (and (pk a) (after h)))

(test-case "absolute lock: nLockTime is set by the path and checked for finality"
  (define-values (ch c) (locked-coin 'p8 (after-height alice 300)))
  (define pay (spend c #:sign alice #:outputs (to-carol)))
  (define r (try pay))
  (check-equal? (rejected-rule r) 'locktime-final)
  (check-equal? (result-detail r 'need) 301)
  (mine (- 300 102) #:on ch)
  (check-pred accepted? (try pay)))

(test-case "a coin with several paths needs #:path"
  (define-values (ch c) (locked-coin 'p9 (htlc alice bob s 144)))
  (check-exn #rx"several spend paths" (λ () (spend c #:sign bob #:outputs (to-carol)))))

(test-case "unknown policy forms are rejected at expansion"
  (check-exn #rx"not a policy form"
             (λ ()
               (parameterize ([current-namespace (make-base-empty-namespace)])
                 (namespace-require 'bitcoin/model)
                 (eval '(contract bad (a) (multi 1 a)))))))
