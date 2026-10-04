#lang racket/base
;; Known-answer tests for the real crypto used by lowering.

(require rackunit
         file/sha1
         "../private/real/hash.rkt"
         "../private/real/secp256k1.rkt")

(define (hex b) (bytes->hex-string b))

(check-equal? (hex (ripemd160 #"")) "9c1185a5c5e9fc54612808977ee8f548b2258d31")
(check-equal? (hex (ripemd160 #"abc")) "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc")
(check-equal? (hex (ripemd160 #"abcdefghijklmnopqrstuvwxyz")) "f71c27109c692c1b56bbdceb5b9d2865b3708dbc")
(check-equal? (hex (ripemd160 (make-bytes 1000000 (char->integer #\a))))
              "52783243c1697bdbe16d37f97f68f08325dc1528")

;; RFC 4231 test case 2.
(check-equal? (hex (hmac-sha256 #"Jefe" #"what do ya want for nothing?"))
              "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")

(check-equal? (hex (pubkey 1)) "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")
(check-equal? (hex (pubkey 3)) "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")

;; Widely used RFC6979 secp256k1 vectors (e.g. python-ecdsa, bitcoinjs).
(check-equal? (hex (ecdsa-sign 1 (sha256 #"Satoshi Nakamoto")))
              (string-append "3045022100934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8"
                             "02202442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"))
(check-equal? (hex (ecdsa-sign (- curve-order 1) (sha256 #"Satoshi Nakamoto")))
              (string-append "3045022100fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0"
                             "02206b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5"))

;; BIP340 test vectors 0 and 1.
(check-equal? (hex (xonly-pubkey 3)) "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")
(check-equal? (hex (schnorr-sign 3 (make-bytes 32 0) (make-bytes 32 0)))
              (string-append "e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215"
                             "25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0"))
(check-equal? (hex (schnorr-sign #xb7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef
                                 (hex-string->bytes "243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89")
                                 (hex-string->bytes "0000000000000000000000000000000000000000000000000000000000000001")))
              (string-append "6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de3341"
                             "8906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a"))
