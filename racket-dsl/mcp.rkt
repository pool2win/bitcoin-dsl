#lang racket/base
;; MCP server: one persistent bitcoin/conform session over stdio.
;;
;; Speaks JSON-RPC 2.0 with one message per line. Tools: eval, snapshot,
;; restore, explain, describe. Run with: racket -l bitcoin/mcp

(require json
         racket/list
         racket/port
         racket/pretty
         racket/string)

(provide make-session
         handle-message
         serve)

(module+ main
  (serve (current-input-port) (current-output-port)))

;; Session

;; ns is a namespace running bitcoin/conform, with its own chain state.
;; snapshots maps snapshot ids to snapshot values.
(struct session (ns snapshots [next-snapshot #:mutable]))

(define (make-session)
  (define ns (make-base-empty-namespace))
  (parameterize ([current-namespace ns])
    (namespace-require 'bitcoin/conform))
  (session ns (make-hash) 1))

(define (ns-ref s name) (namespace-variable-value name #t #f (session-ns s)))

(define eval-timeout 300)
(define max-output 20000)

;; Evaluates every form in code, in order, stopping at the first error.
;; Returns (values text error?): printed results and output, or the error.
(define (session-eval s code)
  (define out (open-output-string))
  (define (render v) (write-string (show v) out))
  (define result
    (call-with-time-limit
     eval-timeout
     (λ ()
       (with-handlers ([exn:fail? (λ (e) (list 'error (exn-message e)))]
                       [exn:break? (λ (e) (list 'error "interrupted"))])
         (parameterize ([current-namespace (session-ns s)]
                        [current-output-port out]
                        [current-error-port out]
                        [read-accept-reader #f]
                        [read-accept-lang #f])
           (define forms (with-input-from-string code (λ () (for/list ([f (in-port read)]) f))))
           (for ([f (in-list forms)])
             (call-with-values (λ () (eval f))
                               (λ vs (for ([v (in-list vs)] #:unless (void? v)) (render v)))))
           'ok)))))
  (define text (truncate-text (get-output-string out)))
  (cond
    [(eq? result 'ok) (values (if (string=? text "") "ok (no values)" text) #f)]
    [(eq? result 'timeout) (values (string-append (fresh-line text) (format "error: timed out after ~as" eval-timeout)) #t)]
    [else (values (string-append (fresh-line text) "error: " (second result)) #t)]))

(define (fresh-line text)
  (if (or (string=? text "") (string-suffix? text "\n")) text (string-append text "\n")))

(define (call-with-time-limit secs thunk)
  (define ch (make-channel))
  (define t (thread (λ () (channel-put ch (thunk)))))
  (or (sync/timeout secs ch)
      (begin (kill-thread t) 'timeout)))

(define (truncate-text s)
  (if (<= (string-length s) max-output)
      s
      (string-append (substring s 0 max-output)
                     (format "\n... truncated ~a more characters" (- (string-length s) max-output)))))

;; A list of lists (explain steps, branches, utxos) prints one element per
;; line, so keyword/value pairs stay together; anything else is printed
;; as the REPL would.
(define (show v)
  (with-output-to-string
    (λ ()
      (cond
        [(and (pair? v) (list? v) (andmap pair? v))
         (printf "'(")
         (for ([x (in-list v)] [i (in-naturals)])
           (unless (zero? i) (printf "\n "))
           (write x))
         (printf ")\n")]
        [else
         (parameterize ([pretty-print-columns 120]) (pretty-print v))]))))

;; Tools

(define tools
  (list
   (hasheq 'name "describe"
           'description "Describe the Bitcoin DSL. With no topic: purpose, conventions and all forms. Topics: a form name (e.g. define-tx), rules, opcodes, state. Start here."
           'inputSchema (hasheq 'type "object"
                                'properties (hasheq 'topic (hasheq 'type "string"
                                                                   'description "Optional topic"))))
   (hasheq 'name "eval"
           'description "Evaluate DSL forms (Racket s-expressions, #lang bitcoin/conform) in the persistent session. Definitions and chain state persist across calls. Returns each non-void result."
           'inputSchema (hasheq 'type "object"
                                'properties (hasheq 'code (hasheq 'type "string"
                                                                  'description "One or more forms"))
                                'required (list "code")))
   (hasheq 'name "snapshot"
           'description "Capture chain state and the scenario log; returns an id for restore. Racket definitions are not captured."
           'inputSchema (hasheq 'type "object" 'properties (hasheq)))
   (hasheq 'name "restore"
           'description "Return chain state and the scenario log to a snapshot."
           'inputSchema (hasheq 'type "object"
                                'properties (hasheq 'id (hasheq 'type "string"))
                                'required (list "id")))
   (hasheq 'name "explain"
           'description "Explain a validation trace: every rule and opcode run in order, with stacks (top first); the failing rule carries its doc. Pass the #:trace id from a result, or omit for the last trace."
           'inputSchema (hasheq 'type "object"
                                'properties (hasheq 'trace (hasheq 'type "integer"))))))

(define instructions
  (string-join
   '("A live Bitcoin modelling session. Call describe first."
     "Write Racket s-expressions with eval, e.g. (chain mainnet #:rules bitcoin) (keys alice bob)."
     "Results are data: rejections name the consensus rule; use explain on the #:trace id to see why."
     "replay checks the scenario log against a real regtest node.")
   " "))

;; Returns (values text error?).
(define (call-tool s name args)
  (case name
    [("eval") (session-eval s (hash-ref args 'code ""))]
    [("describe")
     (define topic (hash-ref args 'topic #f))
     (values (show ((ns-ref s 'describe) (and topic (not (string=? topic "")) (string->symbol topic)))) #f)]
    [("snapshot")
     (define id (format "s~a" (session-next-snapshot s)))
     (set-session-next-snapshot! s (add1 (session-next-snapshot s)))
     (hash-set! (session-snapshots s) id ((ns-ref s 'snapshot)))
     (values id #f)]
    [("restore")
     (define snap (hash-ref (session-snapshots s) (hash-ref args 'id "") #f))
     (cond [snap ((ns-ref s 'restore) snap) (values "restored" #f)]
           [else (values (format "no snapshot ~s" (hash-ref args 'id "")) #t)])]
    [("explain")
     (define trace (or (hash-ref args 'trace #f) ((ns-ref s 'last-trace))))
     (if trace
         (with-handlers ([exn:fail? (λ (e) (values (exn-message e) #t))])
           (values (show ((ns-ref s 'explain) trace)) #f))
         (values "no trace yet" #t))]
    [else (values (format "unknown tool ~a" name) #t)]))

;; JSON-RPC

(define (reply id result) (hasheq 'jsonrpc "2.0" 'id id 'result result))

(define (reply-error id code message)
  (hasheq 'jsonrpc "2.0" 'id id 'error (hasheq 'code code 'message message)))

;; Returns the response jsexpr, or #f for a notification.
(define (handle-message s msg)
  (define id (hash-ref msg 'id 'null))
  (define method (hash-ref msg 'method ""))
  (define params (hash-ref msg 'params (hasheq)))
  (cond
    [(eq? id 'null) #f]
    [else
     (case method
       [("initialize")
        (reply id (hasheq 'protocolVersion (hash-ref params 'protocolVersion "2025-06-18")
                          'capabilities (hasheq 'tools (hasheq))
                          'serverInfo (hasheq 'name "bitcoin-dsl" 'version "0.1")
                          'instructions instructions))]
       [("ping") (reply id (hasheq))]
       [("tools/list") (reply id (hasheq 'tools tools))]
       [("tools/call")
        (define-values (text error?)
          (with-handlers ([exn:fail? (λ (e) (values (exn-message e) #t))])
            (call-tool s (hash-ref params 'name "") (hash-ref params 'arguments (hasheq)))))
        (reply id (hasheq 'content (list (hasheq 'type "text" 'text text))
                          'isError error?))]
       [else (reply-error id -32601 (format "method not found: ~a" method))])]))

(define (serve in out)
  (define s (make-session))
  (for ([line (in-lines in)] #:unless (string=? (string-trim line) ""))
    (define msg (with-handlers ([exn:fail? (λ (e) #f)]) (string->jsexpr line)))
    (define response
      (if (hash? msg)
          (handle-message s msg)
          (reply-error 'null -32700 "parse error")))
    (when response
      (write-json response out)
      (newline out)
      (flush-output out))))
