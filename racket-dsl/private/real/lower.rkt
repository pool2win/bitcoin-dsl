#lang racket/base
;; Lowering: model values to real keys, scripts, transactions and
;; signatures.
;;
;; Keys and secrets are derived from their names, so every run produces the
;; same bytes. A model signature is lowered by signing the BIP143 or BIP341
;; digest of the fields it committed to, not of the tx it sits in, so a
;; signature that is invalid in the model is invalid on a real node too.
;;
;; Taproot hashes are recomputed for real: tapleaf, tapbranch (children
;; sorted by bytes, where the model sorts by printed form; the tree shape
;; is the same), the TapTweak of the output key, and control blocks.

(require racket/list
         racket/match
         file/sha1
         "../amount.rkt"
         "../crypto.rkt"
         "../values.rkt"
         "../script.rkt"
         "hash.rkt"
         "secp256k1.rkt")

(provide (struct-out exn:unsupported)
         privkey-of
         pubkey-of
         secret-bytes
         lower-value
         lower-script
         lower-spk
         lower-tx
         (struct-out ltx)
         (struct-out lin)
         ltx-txid
         ltx-hex)

;; Raised for anything the real chain cannot express yet, e.g. taproot.
(struct exn:unsupported exn:fail (reason))

(define (unsupported reason)
  (raise (exn:unsupported (format "cannot lower: ~a" reason) (current-continuation-marks) reason)))

;; Keys and secrets

(define (privkey-of k)
  (define d (modulo (bytes->int (sha256 (string->bytes/utf-8 (format "bitcoin-dsl/key/~a" (key-name k)))))
                    curve-order))
  (if (zero? d) 1 d))

(define (pubkey-of k) (pubkey (privkey-of k)))

;; Keys are 33-byte compressed in segwit v0 scripts and 32-byte x-only in
;; tapscript; lowering a taproot input sets this to 'xonly.
(define current-key-format (make-parameter 'compressed))

(define (secret-bytes s)
  (sha256 (string->bytes/utf-8 (format "bitcoin-dsl/secret/~a" (secret-name s)))))

;; Byte encodings

(define (le n size) (integer->integer-bytes n size #f #f))

(define (varint n)
  (cond [(< n #xfd) (bytes n)]
        [(<= n #xffff) (bytes-append #"\xfd" (le n 2))]
        [(<= n #xffffffff) (bytes-append #"\xfe" (le n 4))]
        [else (bytes-append #"\xff" (le n 8))]))

(define (var-bytes b) (bytes-append (varint (bytes-length b)) b))

(define (reverse-bytes b) (apply bytes (reverse (bytes->list b))))

;; Minimal little-endian sign-magnitude encoding (CScriptNum).
(define (scriptnum n)
  (cond
    [(zero? n) #""]
    [else
     (define mag (let loop ([a (abs n)] [acc '()])
                   (if (zero? a) (reverse acc) (loop (arithmetic-shift a -8) (cons (bitwise-and a #xff) acc)))))
     (define top (last mag))
     (apply bytes
            (cond [(bitwise-bit-set? top 7) (append mag (list (if (negative? n) #x80 0)))]
                  [(negative? n) (append (drop-right mag 1) (list (bitwise-ior top #x80)))]
                  [else mag]))]))

;; The minimal push for b, as MINIMALDATA requires.
(define (push-data b)
  (define n (bytes-length b))
  (cond [(zero? n) (bytes 0)]
        [(and (= n 1) (<= 1 (bytes-ref b 0) 16)) (bytes (+ #x50 (bytes-ref b 0)))]
        [(and (= n 1) (= (bytes-ref b 0) #x81)) (bytes #x4f)]
        [(<= n 75) (bytes-append (bytes n) b)]
        [(<= n 255) (bytes-append (bytes #x4c n) b)]
        [else (bytes-append (bytes #x4d) (le n 2) b)]))

;; Values and scripts

(define (lower-value v)
  (match v
    [(? bytes?) v]
    [(? exact-integer?) (scriptnum v)]
    [(? key?) (if (eq? (current-key-format) 'xonly) (xonly-pubkey (privkey-of v)) (pubkey-of v))]
    [(? secret?) (secret-bytes v)]
    [(hashed 'hash160 x) (hash160-bytes (lower-value x))]
    [(hashed 'sha256 x) (sha256 (lower-value x))]
    [(hashed 'tapleaf script) (tapleaf-bytes script)]
    [(hashed 'tapbranch (list a b)) (tapbranch-bytes (lower-value a) (lower-value b))]
    [(hashed 'taptweak (list internal root))
     (define-values (qx parity) (output-key internal (and root (lower-value root))))
     qx]
    [(? list?) (lower-script v)]
    [_ (unsupported (format "value ~s" v))]))

;; Opcode bytes come from the global registry: a script's bytes do not
;; depend on the chain it runs on.
(define (lower-script script)
  (apply bytes-append
         (for/list ([op (in-list script)])
           (match op
             [(list 'push v) (push-data (lower-value v))]
             [(? symbol?)
              (bytes (or (opcode-byte-of op) (unsupported (format "opcode ~a" op))))]))))

;; scriptPubKeys always use compressed keys (a P2WPKH program hashes the
;; compressed key), even while lowering a tapscript witness.
(define (lower-spk spk)
  (parameterize ([current-key-format 'compressed])
    (match spk
      [(list 'v0 program) (bytes-append (bytes 0) (push-data (lower-value program)))]
      [(list 'v1 output-key) (bytes-append (bytes #x51) (push-data (lower-value output-key)))])))

;; Taproot

(define (tapleaf-bytes script)
  (define script-bytes (parameterize ([current-key-format 'xonly]) (lower-script script)))
  (tagged-hash "TapLeaf" (bytes-append (bytes #xc0) (var-bytes script-bytes))))

(define (tapbranch-bytes a b)
  (tagged-hash "TapBranch" (if (bytes<? b a) (bytes-append b a) (bytes-append a b))))

;; The TapTweak scalar for an internal key and merkle root (#f: key only).
(define (taptweak-scalar internal root)
  (bytes->int (tagged-hash "TapTweak" (bytes-append (xonly-pubkey (privkey-of internal)) (or root #"")))))

;; The output key's x-only bytes and parity.
(define (output-key internal root)
  (tweak-pubkey (xonly-pubkey (privkey-of internal)) (taptweak-scalar internal root)))

;; A control block for spending through script: leaf version with the
;; output key's parity, the internal key, then the merkle path.
(define (lower-control c script)
  (define path (for/list ([h (in-list (control-path c))]) (lower-value h)))
  (define root (for/fold ([h (tapleaf-bytes script)]) ([sibling (in-list path)])
                 (tapbranch-bytes h sibling)))
  (define-values (qx parity) (output-key (control-internal c) root))
  (apply bytes-append
         (bytes (+ #xc0 parity))
         (xonly-pubkey (privkey-of (control-internal c)))
         path))

;; Transactions

;; A lowered tx. prev-txid is in display (hex) order.
(struct ltx (version locktime inputs outputs) #:transparent)
(struct lin (prev-txid vout sequence witness) #:transparent)

(define (serialize t witness?)
  (define with-witness? (and witness? (ormap (λ (i) (pair? (lin-witness i))) (ltx-inputs t))))
  (bytes-append
   (le (ltx-version t) 4)
   (if with-witness? #"\x00\x01" #"")
   (varint (length (ltx-inputs t)))
   (apply bytes-append
          (for/list ([i (in-list (ltx-inputs t))])
            (bytes-append (reverse-bytes (hex-string->bytes (lin-prev-txid i)))
                          (le (lin-vout i) 4)
                          (var-bytes #"")
                          (le (lin-sequence i) 4))))
   (varint (length (ltx-outputs t)))
   (apply bytes-append
          (for/list ([o (in-list (ltx-outputs t))])
            (bytes-append (le (first o) 8) (var-bytes (second o)))))
   (if with-witness?
       (apply bytes-append
              (for/list ([i (in-list (ltx-inputs t))])
                (apply bytes-append (varint (length (lin-witness i))) (map var-bytes (lin-witness i)))))
       #"")
   (le (ltx-locktime t) 4)))

(define (ltx-txid t) (bytes->hex-string (reverse-bytes (sha256d (serialize t #f)))))

(define (ltx-hex t) (bytes->hex-string (serialize t #t)))

;; real-outpoint : model outpoint -> (values real-txid vout), or raises
;; exn:unsupported for a coin the caller has no real counterpart for.
(define (lower-tx t real-outpoint)
  (when (tx-coinbase? t) (unsupported "a coinbase is made by the node"))
  (ltx (tx-version t)
       (tx-locktime t)
       (for/list ([in (in-list (tx-inputs t))])
         (define-values (txid vout) (real-outpoint (txin-outpoint in)))
         (lin txid vout (txin-sequence in) (lower-witness (txin-witness in) real-outpoint)))
       (for/list ([o (in-list (tx-outputs t))])
         (list (amount-sats (txout-amount o)) (lower-spk (lock->spk (txout-lock o)))))))

;; A taproot script-path witness ends with the leaf script and control
;; block; its keys are x-only.
(define (lower-witness w real-outpoint)
  (define (item x) (lower-witness-item x real-outpoint))
  (cond
    [(and (pair? w) (control? (last w)))
     (parameterize ([current-key-format 'xonly])
       (append (map item (drop-right w 1))
               (list (lower-control (last w) (list-ref w (- (length w) 2))))))]
    [else (map item w)]))

(define (lower-witness-item item real-outpoint)
  (cond
    [(not (sig? item)) (lower-value item)]
    [(or (assq 'spend-type (sig-fields item)) (assq 'invalid (sig-fields item)))
     (lower-schnorr-sig item real-outpoint)]
    [else
     (bytes-append (ecdsa-sign (privkey-of (sig-key item))
                               (bip143-digest (sig-fields item) real-outpoint))
                   (bytes (sighash-byte (sig-type item))))]))

;; A key-path signature is made with the tweaked key of the spent output;
;; a script-path one with the key itself. SIGHASH_DEFAULT adds no byte.
(define (lower-schnorr-sig s real-outpoint)
  (define fields (sig-fields s))
  (define d
    (if (equal? (assq 'spend-type fields) '(spend-type . key))
        (match (spent-spk fields)
          [(list 'v1 (hashed 'taptweak (list internal root)))
           (tweak-seckey (privkey-of (sig-key s))
                         (taptweak-scalar internal (and root (lower-value root))))])
        (privkey-of (sig-key s))))
  (define sig64 (schnorr-sign d (bip341-digest fields real-outpoint)))
  (if (equal? (sig-type s) '(default))
      sig64
      (bytes-append sig64 (bytes (sighash-byte (sig-type s))))))

;; The signing input's scriptPubKey, from whichever fields carry it.
(define (spent-spk fields)
  (cond [(assoc '(own-prevout spk) fields) => cdr]
        [else (list-ref (cdr (assoc '(inputs spks) fields)) (cdr (assoc '(own-input index) fields)))]))

;; Signatures

(define (sighash-byte type)
  (+ (case (car type)
       [(default) 0]
       [(all) 1]
       [(none) 2]
       [(single) 3])
     (if (memq 'anyonecanpay type) #x80 0)))

;; The BIP143 digest, rebuilt from a commitment. A missing hashPrevouts,
;; hashSequence or hashOutputs field means the digest uses 32 zero bytes.
(define (bip143-digest fields real-outpoint)
  (define (field k) (cdr (or (assoc k fields) (unsupported (format "commitment without ~a" k)))))
  (define (has? k) (and (assoc k fields) #t))
  (define zero (make-bytes 32 0))
  (define (outpoint-bytes op)
    (define-values (txid vout) (real-outpoint op))
    (bytes-append (reverse-bytes (hex-string->bytes txid)) (le vout 4)))
  (define (output-bytes o)
    (bytes-append (le (amount-sats (first o)) 8) (var-bytes (lower-spk (second o)))))
  (sha256d
   (bytes-append
    (le (field 'version) 4)
    (if (has? '(inputs outpoints))
        (sha256d (apply bytes-append (map outpoint-bytes (field '(inputs outpoints)))))
        zero)
    (if (has? '(inputs sequences))
        (sha256d (apply bytes-append (map (λ (s) (le s 4)) (field '(inputs sequences)))))
        zero)
    (outpoint-bytes (field '(own-input outpoint)))
    (var-bytes (lower-script (field '(own-prevout script))))
    (le (amount-sats (field '(own-prevout amount))) 8)
    (le (field '(own-input sequence)) 4)
    (cond [(has? '(outputs all)) (sha256d (apply bytes-append (map output-bytes (field '(outputs all)))))]
          [(has? '(own-output)) (sha256d (output-bytes (field '(own-output))))]
          [else zero])
    (le (field 'locktime) 4)
    (le (sighash-byte (field 'sighash-type)) 4))))

;; The BIP341 digest, rebuilt from a commitment. A commitment marked
;; invalid (SINGLE with no matching output) has no valid signature, so any
;; digest will do: the node must reject whatever is signed.
(define (bip341-digest fields real-outpoint)
  (define (field k) (cdr (or (assoc k fields) (unsupported (format "commitment without ~a" k)))))
  (define (has? k) (and (assoc k fields) #t))
  (define (outpoint-bytes op)
    (define-values (txid vout) (real-outpoint op))
    (bytes-append (reverse-bytes (hex-string->bytes txid)) (le vout 4)))
  (define (output-bytes o)
    (bytes-append (le (amount-sats (first o)) 8) (var-bytes (lower-spk (second o)))))
  (define (concat f xs) (apply bytes-append (map f xs)))
  (cond
    [(has? 'invalid) (make-bytes 32 0)]
    [else
     (define type (field 'sighash-type))
     (define script-path? (eq? (field 'spend-type) 'script))
     (tagged-hash
      "TapSighash"
      (bytes-append
       (bytes 0 (sighash-byte type))
       (le (field 'version) 4)
       (le (field 'locktime) 4)
       (if (has? '(inputs outpoints))
           (bytes-append (sha256 (concat outpoint-bytes (field '(inputs outpoints))))
                         (sha256 (concat (λ (a) (le (amount-sats a) 8)) (field '(inputs amounts))))
                         (sha256 (concat (λ (spk) (var-bytes (lower-spk spk))) (field '(inputs spks))))
                         (sha256 (concat (λ (n) (le n 4)) (field '(inputs sequences)))))
           #"")
       (if (has? '(outputs all)) (sha256 (concat output-bytes (field '(outputs all)))) #"")
       (bytes (if script-path? 2 0))
       (if (has? '(own-input index))
           (le (field '(own-input index)) 4)
           (bytes-append (outpoint-bytes (field '(own-input outpoint)))
                         (le (amount-sats (field '(own-prevout amount))) 8)
                         (var-bytes (lower-spk (field '(own-prevout spk))))
                         (le (field '(own-input sequence)) 4)))
       (if (has? '(own-output)) (sha256 (output-bytes (field '(own-output)))) #"")
       (if script-path?
           (bytes-append (lower-value (field '(own-leaf))) (bytes 0) (le #xffffffff 4))
           #"")))]))
