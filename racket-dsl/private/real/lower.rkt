#lang racket/base
;; Lowering: model values to real keys, scripts, transactions and
;; signatures.
;;
;; Keys and secrets are derived from their names, so every run produces the
;; same bytes. A model signature is lowered by signing the BIP143 digest of
;; the fields it committed to, not of the tx it sits in, so a signature
;; that is invalid in the model is invalid on a real node too.

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

(define (lower-value v opcodes)
  (match v
    [(? bytes?) v]
    [(? exact-integer?) (scriptnum v)]
    [(? key?) (pubkey-of v)]
    [(? secret?) (secret-bytes v)]
    [(hashed 'hash160 x) (hash160-bytes (lower-value x opcodes))]
    [(hashed 'sha256 x) (sha256 (lower-value x opcodes))]
    [(? list?) (lower-script v opcodes)]
    [_ (unsupported (format "value ~s" v))]))

;; Opcode bytes come from the consensus value's opcode table.
(define (lower-script script opcodes)
  (apply bytes-append
         (for/list ([op (in-list script)])
           (match op
             [(list 'push v) (push-data (lower-value v opcodes))]
             [(? symbol?)
              (define oc (hash-ref opcodes op (λ () (unsupported (format "opcode ~a" op)))))
              (bytes (opcode-byte oc))]))))

(define (lower-spk spk opcodes)
  (match spk
    [(list 'v0 program) (bytes-append (bytes 0) (push-data (lower-value program opcodes)))]
    [_ (unsupported "taproot output")]))

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
(define (lower-tx t opcodes real-outpoint)
  (when (tx-coinbase? t) (unsupported "a coinbase is made by the node"))
  (ltx (tx-version t)
       (tx-locktime t)
       (for/list ([in (in-list (tx-inputs t))])
         (when (eq? (lock-spend-version (coin-lock (txin-coin in))) 'v1) (unsupported "taproot spend"))
         (define-values (txid vout) (real-outpoint (txin-outpoint in)))
         (lin txid vout (txin-sequence in)
              (for/list ([item (in-list (txin-witness in))])
                (lower-witness-item item opcodes real-outpoint))))
       (for/list ([o (in-list (tx-outputs t))])
         (list (amount-sats (txout-amount o)) (lower-spk (lock->spk (txout-lock o)) opcodes)))))

(define (lower-witness-item item opcodes real-outpoint)
  (if (sig? item)
      (bytes-append (ecdsa-sign (privkey-of (sig-key item))
                                (bip143-digest (sig-fields item) opcodes real-outpoint))
                    (bytes (sighash-byte (sig-type item))))
      (lower-value item opcodes)))

;; Signatures

(define (sighash-byte type)
  (+ (case (car type)
       [(all) 1]
       [(none) 2]
       [(single) 3]
       [else (unsupported (format "sighash ~a outside taproot" type))])
     (if (memq 'anyonecanpay type) #x80 0)))

;; The BIP143 digest, rebuilt from a commitment. A missing hashPrevouts,
;; hashSequence or hashOutputs field means the digest uses 32 zero bytes.
(define (bip143-digest fields opcodes real-outpoint)
  (when (or (assq 'spend-type fields) (assq 'invalid fields)) (unsupported "taproot signature"))
  (define (field k) (cdr (or (assoc k fields) (unsupported (format "commitment without ~a" k)))))
  (define (has? k) (and (assoc k fields) #t))
  (define zero (make-bytes 32 0))
  (define (outpoint-bytes op)
    (define-values (txid vout) (real-outpoint op))
    (bytes-append (reverse-bytes (hex-string->bytes txid)) (le vout 4)))
  (define (output-bytes o)
    (bytes-append (le (amount-sats (first o)) 8) (var-bytes (lower-spk (second o) opcodes))))
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
    (var-bytes (lower-script (field '(own-prevout script)) opcodes))
    (le (amount-sats (field '(own-prevout amount))) 8)
    (le (field '(own-input sequence)) 4)
    (cond [(has? '(outputs all)) (sha256d (apply bytes-append (map output-bytes (field '(outputs all)))))]
          [(has? '(own-output)) (sha256d (output-bytes (field '(own-output))))]
          [else zero])
    (le (field 'locktime) 4)
    (le (sighash-byte (field 'sighash-type)) 4))))
