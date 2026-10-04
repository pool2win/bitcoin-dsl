#lang racket/base
;; secp256k1 in plain Racket: compressed and x-only public keys,
;; deterministic (RFC6979) low-S ECDSA in DER, BIP340 Schnorr, and the
;; BIP341 key tweak. Not constant time; this is for regtest replay with
;; throwaway keys, never real funds.

(require "hash.rkt")

(provide curve-order
         pubkey
         ecdsa-sign
         xonly-pubkey
         schnorr-sign
         tweak-pubkey
         tweak-seckey
         int->bytes32
         bytes->int)

(define p #xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f)
(define curve-order #xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141)
(define gx #x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798)
(define gy #x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8)

(define (expt-mod b e m)
  (let loop ([b (modulo b m)] [e e] [acc 1])
    (cond [(zero? e) acc]
          [(odd? e) (loop (modulo (* b b) m) (arithmetic-shift e -1) (modulo (* acc b) m))]
          [else (loop (modulo (* b b) m) (arithmetic-shift e -1) acc)])))

(define (inv x m) (expt-mod x (- m 2) m))

;; Points in Jacobian coordinates (x y z); #f is the point at infinity.

(define (jdouble pt)
  (cond
    [(not pt) #f]
    [else
     (define-values (x y z) (apply values pt))
     (if (zero? y)
         #f
         (let* ([y2 (modulo (* y y) p)]
                [s (modulo (* 4 x y2) p)]
                [m (modulo (* 3 x x) p)]
                [x3 (modulo (- (* m m) (* 2 s)) p)]
                [y3 (modulo (- (* m (- s x3)) (* 8 y2 y2)) p)]
                [z3 (modulo (* 2 y z) p)])
           (list x3 y3 z3)))]))

(define (jadd a b)
  (cond
    [(not a) b]
    [(not b) a]
    [else
     (define-values (x1 y1 z1) (apply values a))
     (define-values (x2 y2 z2) (apply values b))
     (define z1z1 (modulo (* z1 z1) p))
     (define z2z2 (modulo (* z2 z2) p))
     (define u1 (modulo (* x1 z2z2) p))
     (define u2 (modulo (* x2 z1z1) p))
     (define s1 (modulo (* y1 z2 z2z2) p))
     (define s2 (modulo (* y2 z1 z1z1) p))
     (cond
       [(= u1 u2) (if (= s1 s2) (jdouble a) #f)]
       [else
        (define h (modulo (- u2 u1) p))
        (define r (modulo (- s2 s1) p))
        (define hh (modulo (* h h) p))
        (define hhh (modulo (* h hh) p))
        (define x3 (modulo (- (* r r) hhh (* 2 u1 hh)) p))
        (define y3 (modulo (- (* r (- (* u1 hh) x3)) (* s1 hhh)) p))
        (list x3 y3 (modulo (* h z1 z2) p))])]))

(define (scalar-mult k pt)
  (for/fold ([acc #f]) ([i (in-range (sub1 (integer-length k)) -1 -1)])
    (define d (jdouble acc))
    (if (bitwise-bit-set? k i) (jadd d pt) d)))

(define (affine pt)
  (define-values (x y z) (apply values pt))
  (define zi (inv z p))
  (define zi2 (modulo (* zi zi) p))
  (values (modulo (* x zi2) p) (modulo (* y zi2 zi) p)))

(define g (list gx gy 1))

(define (int->bytes32 n)
  (apply bytes (for/list ([i (in-range 31 -1 -1)]) (bitwise-and (arithmetic-shift n (* -8 i)) #xff))))

(define (bytes->int b)
  (for/fold ([n 0]) ([x (in-bytes b)]) (+ (* n 256) x)))

;; The 33-byte compressed public key for private key d.
(define (pubkey d)
  (define-values (x y) (affine (scalar-mult d g)))
  (bytes-append (bytes (if (even? y) 2 3)) (int->bytes32 x)))

;; RFC6979 section 3.2 with HMAC-SHA256, for a 32-byte digest.
(define (rfc6979-nonce d digest)
  (define x (int->bytes32 d))
  (define h1 (int->bytes32 (modulo (bytes->int digest) curve-order)))
  (let* ([v (make-bytes 32 1)]
         [k (make-bytes 32 0)]
         [k (hmac-sha256 k (bytes-append v #"\0" x h1))]
         [v (hmac-sha256 k v)]
         [k (hmac-sha256 k (bytes-append v #"\1" x h1))]
         [v (hmac-sha256 k v)])
    (let loop ([k k] [v v])
      (define v2 (hmac-sha256 k v))
      (define candidate (bytes->int v2))
      (if (< 0 candidate curve-order)
          candidate
          (let* ([k (hmac-sha256 k (bytes-append v2 #"\0"))])
            (loop k (hmac-sha256 k v2)))))))

;; A DER-encoded low-S ECDSA signature of a 32-byte digest.
(define (ecdsa-sign d digest)
  (define z (bytes->int digest))
  (let loop ([k (rfc6979-nonce d digest)])
    (define-values (x y) (affine (scalar-mult k g)))
    (define r (modulo x curve-order))
    (define s (modulo (* (inv k curve-order) (+ z (* r d))) curve-order))
    (if (or (zero? r) (zero? s))
        (loop (add1 k))
        (der r (if (> s (quotient curve-order 2)) (- curve-order s) s)))))

(define (der-int n)
  (define raw (let loop ([n n] [acc '()]) (if (zero? n) acc (loop (arithmetic-shift n -8) (cons (bitwise-and n #xff) acc)))))
  (define body (if (>= (car raw) #x80) (cons 0 raw) raw))
  (apply bytes #x02 (length body) body))

(define (der r s)
  (define body (bytes-append (der-int r) (der-int s)))
  (bytes-append (bytes #x30 (bytes-length body)) body))

;; BIP340 and BIP341

(define (xonly-pubkey d)
  (define-values (x y) (affine (scalar-mult d g)))
  (int->bytes32 x))

;; The point with x coordinate x and even y.
(define (lift-x x)
  (define c (modulo (+ (expt-mod x 3 p) 7) p))
  (define y (expt-mod c (quotient (+ p 1) 4) p))
  (unless (= (modulo (* y y) p) c) (error 'lift-x "x is not on the curve"))
  (list x (if (even? y) y (- p y)) 1))

;; d negated if needed so that d*G has even y, as BIP340 keys are x-only.
(define (even-y-seckey d)
  (define-values (x y) (affine (scalar-mult d g)))
  (if (even? y) d (- curve-order d)))

(define (bytes-xor a b)
  (apply bytes (for/list ([x (in-bytes a)] [y (in-bytes b)]) (bitwise-xor x y))))

;; A 64-byte BIP340 signature of a 32-byte message. aux defaults to zeros,
;; keeping signatures deterministic.
(define (schnorr-sign d msg [aux (make-bytes 32 0)])
  (define d* (even-y-seckey d))
  (define pb (xonly-pubkey d*))
  (define t (bytes-xor (int->bytes32 d*) (tagged-hash "BIP0340/aux" aux)))
  (define k0 (modulo (bytes->int (tagged-hash "BIP0340/nonce" (bytes-append t pb msg))) curve-order))
  (when (zero? k0) (error 'schnorr-sign "nonce is zero"))
  (define-values (rx ry) (affine (scalar-mult k0 g)))
  (define k (if (even? ry) k0 (- curve-order k0)))
  (define rb (int->bytes32 rx))
  (define e (modulo (bytes->int (tagged-hash "BIP0340/challenge" (bytes-append rb pb msg))) curve-order))
  (bytes-append rb (int->bytes32 (modulo (+ k (* e d*)) curve-order))))

;; Q = lift_x(internal) + t*G. Returns Q's x-only key and y parity (0 even).
(define (tweak-pubkey internal-xonly t)
  (define-values (qx qy) (affine (jadd (lift-x (bytes->int internal-xonly)) (scalar-mult t g))))
  (values (int->bytes32 qx) (if (even? qy) 0 1)))

;; The private key for Q, for a key-path signature.
(define (tweak-seckey d t)
  (modulo (+ (even-y-seckey d) t) curve-order))
