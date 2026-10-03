#lang racket/base
;; BIP119 template hashes against Bitcoin Inquisition's test vectors
;; (src/test/data/ctvhash.json), for every vector without scriptSigs (the
;; model has none). Skipped when the Inquisition source is not present.

(require rackunit
         racket/file
         racket/list
         file/sha1
         json
         "../private/real/lower.rkt")

(define vectors-path
  (build-path (find-system-path 'home-dir) "projects" "bitcoin-inquisition" "src" "test" "data" "ctvhash.json"))

;; Version, locktime, sequences, scriptSig presence and serialized outputs
;; of a raw tx.
(define (parse-tx b)
  (define pos 0)
  (define (take-bytes n) (begin0 (subbytes b pos (+ pos n)) (set! pos (+ pos n))))
  (define (u n) (integer-bytes->integer (take-bytes n) #f #f))
  (define (varint)
    (define x (bytes-ref b pos))
    (set! pos (add1 pos))
    (case x [(#xfd) (u 2)] [(#xfe) (u 4)] [(#xff) (u 8)] [else x]))
  (define version (integer-bytes->integer (take-bytes 4) #t #f))
  (define segwit? (and (= (bytes-ref b pos) 0) (= (bytes-ref b (add1 pos)) 1)))
  (when segwit? (set! pos (+ pos 2)))
  (define-values (sequences script-sigs?)
    (for/fold ([seqs '()] [sigs? #f] #:result (values (reverse seqs) sigs?))
              ([_ (in-range (varint))])
      (take-bytes 36)
      (define sig-len (varint))
      (take-bytes sig-len)
      (values (cons (u 4) seqs) (or sigs? (positive? sig-len)))))
  (define outputs
    (for/list ([_ (in-range (varint))])
      (define start pos)
      (take-bytes 8)
      (take-bytes (varint))
      (subbytes b start pos)))
  (when segwit?
    (for ([_ (in-range (length sequences))])
      (for ([_ (in-range (varint))]) (take-bytes (varint)))))
  (values version (u 4) sequences script-sigs? outputs))

(when (file-exists? vectors-path)
  (define checked
    (for*/sum ([v (in-list (rest (read-json (open-input-file vectors-path))))]
               #:when (hash? v))
      (define-values (version locktime sequences script-sigs? outputs)
        (parse-tx (hex-string->bytes (hash-ref v 'hex_tx))))
      (if script-sigs?
          0
          (for/sum ([index (in-list (hash-ref v 'spend_index))]
                    [expected (in-list (hash-ref v 'result))])
            (check-equal? (bytes->hex-string (bip119-hash version locktime sequences outputs index))
                          expected)
            1))))
  (check-true (> checked 20) (format "checked ~a vectors" checked)))
