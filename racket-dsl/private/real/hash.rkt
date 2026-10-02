#lang racket/base
;; Hash functions used by lowering: SHA256 (from racket/base), double
;; SHA256, RIPEMD160, HASH160 and HMAC-SHA256.

(provide sha256
         sha256d
         ripemd160
         hash160-bytes
         hmac-sha256)

(define (sha256 b) (sha256-bytes b))

(define (sha256d b) (sha256 (sha256 b)))

(define (hash160-bytes b) (ripemd160 (sha256 b)))

(define (hmac-sha256 key msg)
  (define k (let ([k (if (> (bytes-length key) 64) (sha256 key) key)])
              (bytes-append k (make-bytes (- 64 (bytes-length k)) 0))))
  (define (xor-pad pad) (apply bytes (for/list ([b (in-bytes k)]) (bitwise-xor b pad))))
  (sha256 (bytes-append (xor-pad #x5c) (sha256 (bytes-append (xor-pad #x36) msg)))))

;; RIPEMD160

(define mask32 #xffffffff)
(define (add32 . xs) (bitwise-and (apply + xs) mask32))
(define (not32 x) (bitwise-xor x mask32))
(define (rol x n) (bitwise-and (bitwise-ior (arithmetic-shift x n) (arithmetic-shift x (- n 32))) mask32))

(define (f j x y z)
  (cond [(< j 16) (bitwise-xor x y z)]
        [(< j 32) (bitwise-ior (bitwise-and x y) (bitwise-and (not32 x) z))]
        [(< j 48) (bitwise-xor (bitwise-ior x (not32 y)) z)]
        [(< j 64) (bitwise-ior (bitwise-and x z) (bitwise-and y (not32 z)))]
        [else (bitwise-xor x (bitwise-ior y (not32 z)))]))

(define k-left (vector #x00000000 #x5a827999 #x6ed9eba1 #x8f1bbcdc #xa953fd4e))
(define k-right (vector #x50a28be6 #x5c4dd124 #x6d703ef3 #x7a6d76e9 #x00000000))

(define r-left
  (vector 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
          7 4 13 1 10 6 15 3 12 0 9 5 2 14 11 8
          3 10 14 4 9 15 8 1 2 7 0 6 13 11 5 12
          1 9 11 10 0 8 12 4 13 3 7 15 14 5 6 2
          4 0 5 9 7 12 2 10 14 1 3 8 11 6 15 13))

(define r-right
  (vector 5 14 7 0 9 2 11 4 13 6 15 8 1 10 3 12
          6 11 3 7 0 13 5 10 14 15 8 12 4 9 1 2
          15 5 1 3 7 14 6 9 11 8 12 2 10 0 4 13
          8 6 4 1 3 11 15 0 5 12 2 13 9 7 10 14
          12 15 10 4 1 5 8 7 6 2 13 14 0 3 9 11))

(define s-left
  (vector 11 14 15 12 5 8 7 9 11 13 14 15 6 7 9 8
          7 6 8 13 11 9 7 15 7 12 15 9 11 7 13 12
          11 13 6 7 14 9 13 15 14 8 13 6 5 12 7 5
          11 12 14 15 14 15 9 8 9 14 5 6 8 6 5 12
          9 15 5 11 6 8 13 12 5 12 13 14 11 8 5 6))

(define s-right
  (vector 8 9 9 11 13 15 15 5 7 7 8 11 14 14 12 6
          9 13 15 7 12 8 9 11 7 7 12 7 6 15 13 11
          9 7 15 11 8 6 6 14 12 13 5 14 13 13 7 5
          15 5 8 11 14 14 6 14 6 9 12 9 12 5 15 8
          8 5 12 9 12 5 14 6 8 13 6 5 15 13 11 11))

(define (ripemd160 msg)
  ;;* Pad as MD4 does: a 1 bit, zeros to 56 mod 64 bytes, then the bit length little-endian.
  (define len (bytes-length msg))
  (define padded
    (bytes-append msg #"\x80"
                  (make-bytes (modulo (- 55 len) 64) 0)
                  (integer->integer-bytes (* 8 len) 8 #f #f)))
  ;;* Run each 64-byte block through the left and right lines, then fold both into the state.
  (define-values (h0 h1 h2 h3 h4)
    (for/fold ([h0 #x67452301] [h1 #xefcdab89] [h2 #x98badcfe] [h3 #x10325476] [h4 #xc3d2e1f0])
              ([block (in-range 0 (bytes-length padded) 64)])
      (define x (for/vector ([i 16]) (integer-bytes->integer padded #f #f (+ block (* 4 i)) (+ block (* 4 i) 4))))
      (define-values (al bl cl dl el)
        (for/fold ([a h0] [b h1] [c h2] [d h3] [e h4]) ([j 80])
          (define t (add32 (rol (add32 a (f j b c d) (vector-ref x (vector-ref r-left j))
                                       (vector-ref k-left (quotient j 16)))
                                (vector-ref s-left j))
                           e))
          (values e t b (rol c 10) d)))
      (define-values (ar br cr dr er)
        (for/fold ([a h0] [b h1] [c h2] [d h3] [e h4]) ([j 80])
          (define t (add32 (rol (add32 a (f (- 79 j) b c d) (vector-ref x (vector-ref r-right j))
                                       (vector-ref k-right (quotient j 16)))
                                (vector-ref s-right j))
                           e))
          (values e t b (rol c 10) d)))
      (values (add32 h1 cl dr) (add32 h2 dl er) (add32 h3 el ar) (add32 h4 al br) (add32 h0 bl cr))))
  ;;* Emit the state words little-endian.
  (apply bytes-append (for/list ([h (list h0 h1 h2 h3 h4)]) (integer->integer-bytes h 4 #f #f))))
