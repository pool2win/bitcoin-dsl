#lang bitcoin/model
;; Taproot: key and script path spends, BIP341 commitments, tapscript.

(require rackunit
         (only-in "../private/values.rkt" make-tx tx-chain tx-name tx-version tx-locktime
                  tx-outputs tx-inputs txin txin-coin txin-sequence txin-witness control control-internal))

(chain mainnet #:rules bitcoin)
(keys alice bob carol nobody)

(contract htlc (sender receiver secret timeout)
  (or [claim  (and (pk receiver) (sha256 secret))]
      [refund (and (pk sender) (older timeout))]))

(contract single-key (k)
  (pk k))

(define s (secret 's1))

(define ca (first (mine 1 #:on mainnet #:to alice)))
(define cb (first (mine 1 #:on mainnet #:to bob)))
(mine 100 #:on mainnet)

(define-tx fund
  #:inputs  ([ca #:sign alice] [cb #:sign bob])
  #:outputs ([key-only   (tr alice)                                   (btc 20)]
             [with-htlc  (tr carol #:leaves (list (htlc alice bob s 144)
                                                  (single-key alice)
                                                  (single-key bob)))  (btc 20)]
             [key-only-b (tr bob)                                     (btc 20)]
             [leaf-only  (tr nobody #:leaves (list (single-key alice))) (btc 39.9)]))
(check-pred accepted? (confirm fund))

(define (to-carol amt) (list (output 'paid (wpkh carol) amt)))

(test-case "key path spend, default sighash"
  (define t (spend key-only #:sign alice #:outputs (to-carol (btc 19.99))))
  (check-pred accepted? (try t))
  (check-equal? (commits (sig-of t 0))
                '(version locktime
                  (inputs outpoints) (inputs amounts) (inputs spks) (inputs sequences)
                  (outputs all)
                  spend-type
                  (own-input index))))

(test-case "branches: key path, then leaves named after their contracts"
  (check-equal? (map branch-name (branches with-htlc))
                '(key htlc/claim htlc/refund single-key-1 single-key-2))
  (check-equal? (utxos #:spendable-by bob)
                (list with-htlc key-only-b)))

(test-case "script path spends through each leaf"
  (check-pred accepted? (try (spend with-htlc #:path 'htlc/claim #:sign bob #:reveal s
                                    #:outputs (to-carol (btc 19.99)))))
  (check-pred accepted? (try (spend with-htlc #:path 'single-key-2 #:sign bob
                                    #:outputs (to-carol (btc 19.99)))))
  (check-pred accepted? (try (spend with-htlc #:path 'key #:sign carol
                                    #:outputs (to-carol (btc 19.99)))))
  (define early (try (spend with-htlc #:path 'htlc/refund #:sign alice
                            #:outputs (to-carol (btc 19.99)))))
  (check-equal? (rejected-rule early) 'sequence-lock))

(test-case "a script path signature commits to the leaf"
  (define t (spend leaf-only #:path 'single-key #:sign alice #:outputs (to-carol (btc 39.89))))
  (check-pred accepted? (try t))
  (check-not-false (member '(own-leaf) (commits (sig-of t 0))))
  (check-not-false (member 'codesep-position (commits (sig-of t 0)))))

(test-case "tapscript: a non-empty bad signature fails CHECKSIG itself"
  (define t (spend leaf-only #:path 'single-key #:sign alice #:outputs (to-carol (btc 39.89))))
  (define r (try (edit t '(output paid amount) (btc 39))))
  (check-equal? (rejected-rule r) 'checksig)
  (check-equal? (result-detail r 'cause) 'commitment-mismatch))

(test-case "tapscript: an empty signature just pushes false"
  (define r (try (spend with-htlc #:path 'htlc/claim #:sign alice #:reveal s
                        #:outputs (to-carol (btc 19.99)))))
  (check-equal? (rejected-rule r) 'checksigverify)
  (check-equal? (result-detail r 'cause) 'empty-signature))

(test-case "key path: a bad signature is rejected"
  (define t (spend key-only #:sign alice #:outputs (to-carol (btc 19.99))))
  (define r (try (edit t '(output paid amount) (btc 19))))
  (check-equal? (rejected-rule r) 'key-path-sig)
  (check-equal? (result-detail r 'cause) 'commitment-mismatch))

(test-case "a control block for another internal key does not commit to the output"
  (define t (spend leaf-only #:path 'single-key #:sign alice #:outputs (to-carol (btc 39.89))))
  (define in (first (tx-inputs t)))
  (define w (txin-witness in))
  (define forged (append (drop-right w 1) (list (control alice '()))))
  (define t2 (make-tx (tx-chain t) #f (tx-version t) (tx-locktime t)
                      (list (txin (txin-coin in) (txin-sequence in) forged))
                      (tx-outputs t)))
  (check-equal? (rejected-rule (try t2)) 'taproot-commitment))

(test-case "SINGLE with no output at the input's index is invalid (BIP341)"
  (define t (spend (list (input key-only #:sign alice #:sighash 'single)
                         (input key-only-b #:sign bob #:sighash 'single))
                   #:outputs (to-carol (btc 39.9))))
  (define r (try t))
  (check-equal? (rejected-rule r) 'key-path-sig)
  (check-equal? (rejected-input r) 1)
  (check-equal? (result-detail r 'cause) 'single-without-output))

(test-case "default is a taproot-only sighash type"
  (check-exn #rx"default is a taproot sighash type"
             (λ () (spend (first (mine 1 #:on mainnet #:to alice)) #:sign alice #:sighash 'default
                          #:outputs (to-carol (btc 1))))))

;; free-fields agrees with verification, as for BIP143 in sighash.rkt.

(define value-edits
  `(((output a amount) (output 0 amount) ,(btc 9.9))
    ((output a lock)   (output 0 lock)   ,(wpkh nobody))
    ((output b amount) (output 1 amount) ,(btc 29.8))
    ((output b lock)   (output 1 lock)   ,(wpkh nobody))
    ((input 0 sequence) (input 0 sequence) #xfffffffe)
    ((input 1 sequence) (input 1 sequence) #xfffffffe)
    (version  version  1)
    (locktime locktime 1)))

(define flag-sets
  '((default) (all) (all anyonecanpay) (none) (none anyonecanpay) (single) (single anyonecanpay)))

;; Two taproot inputs signed with the same flags: by key path, or both
;; through a script path.
(define (signed-with flags kind)
  (define ins
    (case kind
      [(key) (list (input key-only #:sign alice #:sighash flags)
                   (input key-only-b #:sign bob #:sighash flags))]
      [(script) (list (input with-htlc #:path 'single-key-1 #:sign alice #:sighash flags)
                      (input leaf-only #:path 'single-key #:sign alice #:sighash flags))]))
  (spend ins #:outputs (list (output 'a (wpkh carol) (btc 10))
                             (output 'b (wpkh carol) (btc 29.9)))))

(for* ([kind '(key script)] [flags (in-list flag-sets)])
  (define t (signed-with flags kind))
  (check-pred accepted? (try t) (format "~a ~a: unedited tx" kind flags))
  (define free (free-fields t))
  (for ([e (in-list value-edits)])
    (define r (try (edit t (second e) (third e))))
    (check-equal? (accepted? r) (and (member (first e) free) #t)
                  (format "~a ~a: ~a free=~a result=~a" kind flags (first e) (member (first e) free) r))))

(test-case "BIP341 commits to every input's sequence under NONE, unlike BIP143"
  (define other (first (mine 1 #:on mainnet #:to bob)))
  (define alice-wpkh (first (mine 1 #:on mainnet #:to alice)))
  (define (with-other c)
    (spend (list (input c #:sign alice #:sighash 'none) (input other)) #:outputs (to-carol (btc 1))))
  (check-not-false (member '(input 1 sequence) (free-fields (with-other alice-wpkh))))
  (check-false (member '(input 1 sequence) (free-fields (with-other key-only)))))
