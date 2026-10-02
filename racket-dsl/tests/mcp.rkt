#lang racket/base
;; The MCP server: scenarios run through the eval tool as an agent would
;; send them, plus snapshot/restore, explain, errors and stdio framing.

(require rackunit
         racket/file
         racket/list
         racket/runtime-path
         racket/port
         racket/string
         racket/system
         json
         "../mcp.rkt")

(define (call s name args)
  (define r (hash-ref (handle-message s (hasheq 'jsonrpc "2.0" 'id 1 'method "tools/call"
                                                'params (hasheq 'name name 'arguments args)))
                      'result))
  (values (hash-ref (first (hash-ref r 'content)) 'text) (hash-ref r 'isError)))

(define (eval-ok s code)
  (define-values (text error?) (call s "eval" (hasheq 'code code)))
  (check-false error? text)
  text)

(define-runtime-path here ".")

;; A scenario file's body, without its #lang line.
(define (scenario-body n)
  (define src (file->string (build-path here (format "scenario-~a.rkt" n))))
  (string-join (rest (string-split src "\n")) "\n"))

(for ([n '(1 2 3)])
  (test-case (format "scenario ~a through eval" n)
    (define s (make-session))
    (define text (eval-ok s (scenario-body n)))
    (check-false (string-contains? text "FAILURE") text)
    (check-false (string-contains? text "ERROR") text)))

(test-case "definitions and chain state persist across calls; snapshot and restore tools"
  (define s (make-session))
  (eval-ok s "(chain mainnet #:rules bitcoin) (keys alice bob)")
  (eval-ok s "(define cb (first (mine 1 #:on mainnet #:to alice)))")
  (define-values (id _e) (call s "snapshot" (hasheq)))
  (eval-ok s "(void (mine 100 #:on mainnet))")
  (check-equal? (eval-ok s "(length (utxos))") "101\n")
  (define-values (restored error?) (call s "restore" (hasheq 'id id)))
  (check-false error?)
  (check-equal? (eval-ok s "(length (utxos))") "1\n"))

(test-case "explain the last trace, or one by id"
  (define s (make-session))
  (eval-ok s "(chain mainnet #:rules bitcoin) (keys alice bob)
              (define cb (first (mine 1 #:on mainnet #:to alice)))
              (try (spend cb #:sign alice #:outputs (list (output 'b (wpkh bob) (btc 49)))))")
  (define-values (last-text e1) (call s "explain" (hasheq)))
  (check-false e1)
  (check-true (string-contains? last-text "(rule coinbase-maturity #:input 0 fail #:need 100 #:have 1"))
  (define-values (by-id e2) (call s "explain" (hasheq 'trace 1)))
  (check-equal? by-id last-text)
  (define-values (missing e3) (call s "explain" (hasheq 'trace 99)))
  (check-true e3))

(test-case "errors are reported, output kept, and the session survives"
  (define s (make-session))
  (define-values (text error?) (call s "eval" (hasheq 'code "(display \"partial\") (car 1)")))
  (check-true error?)
  (check-true (string-prefix? text "partial\nerror: in form 2 of 2 (the forms before it ran; the rest did not): car:"))
  (check-equal? (eval-ok s "(+ 1 2)") "3\n"))

(test-case "describe"
  (define s (make-session))
  (define-values (overview e1) (call s "describe" (hasheq)))
  (check-true (string-contains? overview "conventions"))
  (define-values (form e2) (call s "describe" (hasheq 'topic "define-tx")))
  (check-true (string-contains? form "#:usage"))
  (define-values (rules e3) (call s "describe" (hasheq 'topic "rules")))
  (check-true (string-contains? rules "sequence-lock")))

(test-case "replay through eval"
  (when (find-executable-path "bitcoind")
    (define s (make-session))
    (eval-ok s (scenario-body 1))
    (check-equal? (eval-ok s "(summary (replay (scenario-log) #:targets (hash 'mainnet (regtest))))")
                  "'((confirmed 5)\n (disagree 0)\n (unverified 0))\n")))

(test-case "stdio: initialize, notification, tools/list, call"
  (define racket (find-executable-path "racket"))
  (define-values (proc out in err) (subprocess #f #f #f racket "-l" "bitcoin/mcp"))
  (for ([m (list (hasheq 'jsonrpc "2.0" 'id 1 'method "initialize"
                         'params (hasheq 'protocolVersion "2025-06-18" 'capabilities (hasheq)
                                         'clientInfo (hasheq 'name "test" 'version "0")))
                 (hasheq 'jsonrpc "2.0" 'method "notifications/initialized")
                 (hasheq 'jsonrpc "2.0" 'id 2 'method "tools/list")
                 (hasheq 'jsonrpc "2.0" 'id 3 'method "tools/call"
                         'params (hasheq 'name "eval" 'arguments (hasheq 'code "(btc 1.5)"))))])
    (write-json m in)
    (newline in))
  (close-output-port in)
  (define responses (for/list ([line (in-lines out)]) (string->jsexpr line)))
  (subprocess-wait proc)
  (close-input-port out)
  (close-input-port err)
  (check-equal? (map (λ (r) (hash-ref r 'id)) responses) '(1 2 3))
  (check-equal? (hash-ref (hash-ref (first responses) 'result) 'protocolVersion) "2025-06-18")
  (check-equal? (map (λ (t) (hash-ref t 'name)) (hash-ref (hash-ref (second responses) 'result) 'tools))
                '("describe" "eval" "snapshot" "restore" "explain"))
  (check-equal? (hash-ref (first (hash-ref (hash-ref (third responses) 'result) 'content)) 'text)
                "(btc 1.5)\n"))

(test-case "fixes from the first agent run"
  (define s (make-session))
  ;; Long lists are abbreviated in replies.
  (check-true (string-contains? (eval-ok s "(chain mainnet #:rules bitcoin) (keys alice bob miner) (mine 101 #:on mainnet)")
                                ";; ... 89 more elements (101 in all)"))
  (check-equal? (eval-ok s "(height)") "101\n")
  ;; A user key named miner does not own anonymous coinbases.
  (check-equal? (eval-ok s "(utxos #:spendable-by miner)") "'()\n")
  ;; The failing explain step names the specific rule, which describe documents.
  (eval-ok s "(define cb (first (utxos)))
              (try (spend cb #:sign alice #:outputs (list (output 'b (wpkh bob) (btc 49)))))")
  (define-values (steps _e) (call s "explain" (hasheq)))
  (check-true (string-contains? steps "(rule witness-script #:input 0 fail #:as eval-false #:cause empty-signature"))
  (define-values (doc _e2) (call s "describe" (hasheq 'topic "eval-false")))
  (check-true (string-contains? doc "finished with false on top"))
  ;; add-input names its tx after the original.
  (eval-ok s "(define c2 (second (utxos)))
              (define-tx p #:inputs ([cb #:sign miner #:sighash '(all anyonecanpay)])
                           #:outputs ([o (wpkh bob) (btc 49)]))")
  (check-true (string-contains? (eval-ok s "(add-input p c2)") "#<tx p+input")))

(test-case "fixes from the second agent run"
  (define s (make-session))
  (eval-ok s "(chain mainnet #:rules bitcoin) (keys alice bob)
              (define cb (first (mine 1 #:on mainnet #:to alice))) (void (mine 100 #:on mainnet))
              (define-tx pay #:inputs ([cb #:sign alice]) #:outputs ([o (wpkh bob) (btc 49)]))")
  ;; A commitment mismatch says which fields changed.
  (check-true (string-contains? (eval-ok s "(try (edit pay '(output o amount) (btc 48)))")
                                "#:cause commitment-mismatch #:fields ((outputs all))"))
  (define-values (overview _e) (call s "describe" (hasheq)))
  (check-true (string-contains? overview "(height #:on chain)"))
  (define-values (sighash _e2) (call s "describe" (hasheq 'topic "sighash")))
  (check-true (string-contains? sighash "BIP341")))
