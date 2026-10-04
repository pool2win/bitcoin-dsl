#lang bitcoin/conform
;; sighash-matrix: every spend type x flag set x edit agrees with Core,
;; and the matrix covers both accepted and rejected cells.

(require rackunit)

(if (find-executable-path "bitcoind")
    (let* ([rows (sighash-matrix #:spend-types '(wpkh tr-key tr-script legacy))]
           [cells (filter (λ (r) (not (eq? (car r) 'unsupported))) rows)]
           [find (λ (type flags e)
                   (for/first ([r (in-list cells)]
                               #:when (and (equal? (cadr (memq '#:type r)) type)
                                           (equal? (cadr (memq '#:flags r)) flags)
                                           (equal? (cadr (memq '#:edit r)) e)))
                     (cadr (memq '#:model r))))])
      (check-equal? (length cells) (+ (* 6 13) (* 2 7 13)))
      (check-true (andmap (λ (r) (eq? (car r) 'confirmed)) cells))
      (check-equal? (filter (λ (r) (eq? (car r) 'unsupported)) rows) '((unsupported #:type legacy)))
      (check-true (> (length (filter (λ (r) (eq? (cadr (memq '#:model r)) 'accepted)) cells)) 26))
      (check-true (> (length (filter (λ (r) (pair? (cadr (memq '#:model r)))) cells)) 26))
      (check-equal? (find 'wpkh '(all anyonecanpay) '(inputs append)) 'accepted)
      (check-equal? (find 'wpkh '(all) '(inputs append)) '(rejected eval-false))
      (check-equal? (find 'tr-key '(none) '(output 0 lock)) 'accepted)
      (check-equal? (find 'tr-script '(single) '(output 1 amount)) '(rejected checksig))
      (check-equal? (scenario-log) '()))
    (displayln "skipping sighash matrix: bitcoind not found"))
