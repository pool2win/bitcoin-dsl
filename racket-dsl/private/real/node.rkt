#lang racket/base
;; A throwaway regtest bitcoind: started in a temporary datadir on a free
;; RPC port, driven over JSON-RPC with cookie auth, then stopped and its
;; datadir deleted. It never touches ~/.bitcoin.

(require racket/file
         racket/port
         racket/tcp
         net/http-client
         net/base64
         json)

(provide (struct-out node)
         (struct-out exn:rpc)
         start-node
         stop-node
         rpc)

(struct node (process datadir port))

(struct exn:rpc exn:fail (code))

(define (free-port)
  (define l (tcp-listen 0 4 #t "127.0.0.1"))
  (define-values (_host port _rhost _rport) (tcp-addresses l #t))
  (tcp-close l)
  port)

;; Consensus is what replay checks, so standardness policy and fee floors
;; are relaxed to keep them from showing up as disagreements.
(define default-args
  '("-regtest" "-listen=0" "-server=1" "-disablewallet=1" "-printtoconsole=0"
    "-acceptnonstdtxn=1" "-minrelaytxfee=0" "-blockmintxfee=0" "-dustrelayfee=0"))

(define (start-node #:bitcoind [bitcoind "bitcoind"] #:args [extra '()])
  (define exe (or (find-executable-path bitcoind)
                  (raise-arguments-error 'start-node "bitcoind not found" "bitcoind" bitcoind)))
  (define dir (make-temporary-directory "bitcoin-dsl-regtest-~a"))
  (define port (free-port))
  (define-values (proc out in err)
    (apply subprocess #f #f #f exe
           (format "-datadir=~a" dir) (format "-rpcport=~a" port)
           (append default-args extra)))
  (close-output-port in)
  (for ([p (list out err)]) (thread (λ () (copy-port p (open-output-nowhere)))))
  (define n (node proc dir port))
  ;;* Wait until the RPC server answers, giving up if bitcoind exits or 60s pass.
  (let loop ([tries 0])
    (cond
      [(with-handlers ([exn:fail? (λ (e) #f)]) (rpc n "getblockcount") #t) n]
      [(not (eq? (subprocess-status proc) 'running))
       (delete-directory/files dir #:must-exist? #f)
       (error 'start-node "bitcoind exited with status ~a" (subprocess-status proc))]
      [(> tries 600)
       (stop-node n)
       (error 'start-node "bitcoind RPC did not come up")]
      [else (sleep 0.1) (loop (add1 tries))])))

(define (stop-node n)
  (with-handlers ([exn:fail? void]) (rpc n "stop"))
  (define proc (node-process n))
  (let loop ([tries 0])
    (cond [(not (eq? (subprocess-status proc) 'running)) (void)]
          [(> tries 300) (subprocess-kill proc #t)]
          [else (sleep 0.1) (loop (add1 tries))]))
  (delete-directory/files (node-datadir n) #:must-exist? #f))

(define (rpc n method . params)
  (define cookie (file->bytes (build-path (node-datadir n) "regtest" ".cookie")))
  (define-values (status headers in)
    (http-sendrecv "127.0.0.1" "/"
                   #:port (node-port n)
                   #:method "POST"
                   #:headers (list (string-append "Authorization: Basic "
                                                  (bytes->string/utf-8 (base64-encode cookie #"")))
                                   "Content-Type: application/json")
                   #:data (jsexpr->string (hasheq 'jsonrpc "1.0" 'id 1 'method method 'params params))))
  (define response (read-json in))
  (define err (hash-ref response 'error 'null))
  (if (eq? err 'null)
      (hash-ref response 'result)
      (raise (exn:rpc (format "~a: ~a" method (hash-ref err 'message))
                      (current-continuation-marks)
                      (hash-ref err 'code)))))
