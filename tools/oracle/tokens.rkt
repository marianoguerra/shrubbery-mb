#lang racket/base
;; Dump the reference's token stream for a file, in the form
;; `lib/lexer` dumps its own.
;;
;;   racket tools/oracle/tokens.rkt FILE
;;
;; Uses `lex/status` rather than `lex-all` on purpose: `lex-all` calls its
;; `fail` callback on a failure token, so it can report the first lexical error
;; but not the stream around it. Comparing what the two implementations do with
;; a bad file is exactly what this is for.
(require racket/port racket/file
         (file "../../reference/shrubbery-lib/shrubbery/lex.rkt")
         "canonical.rkt")

;; The `raw` property is attached to the syntax object that stands for the
;; token's TEXT, which for an operator is the inner symbol and not the `(op _)`
;; wrapper. A comment carries none at all -- `make-token` skips it -- so its
;; text is the datum.
(define (tok-raw tok)
  (let loop ([stx (token-value tok)])
    (define r (and (syntax? stx) (syntax-property stx 'raw)))
    (cond
      [(string? r) r]
      [(and (syntax? stx) (pair? (syntax-e stx)))
       (let last-of ([l (syntax-e stx)])
         (if (null? (cdr l)) (loop (car l)) (last-of (cdr l))))]
      [else
       (define e (if (syntax? stx) (syntax-e stx) stx))
       (if (string? e) e (format "~a" e))])))

;; `lex-all` rather than a hand-rolled `lex/status` loop, because `#{...}`
;; escapes need the S-expression handling that only `lex-all` does -- driving
;; `lex/status` directly lands in S-expression mode with no Racket lexer to
;; hand it to. The cost is that `lex-all` calls `fail` on the first failure
;; token, so a file with a lexical error yields a message rather than a stream.
;; That is what the error oracle is for.
(define (dump-tokens src)
  (define in (open-input-string src))
  (port-count-lines! in)
  (define out (open-output-string))
  (define toks
    (lex-all in (lambda (tok msg) (error 'lex "~a" msg))))
  (for ([tok (in-list toks)])
    (define name (token-name/keyword tok))
    (define raw (tok-raw tok))
    (fprintf out "~a\t~a\t~a\t~a\t~a\n"
             name
             ;; `token-line` is the lexer's own synthetic counter, which starts
             ;; at 0. Racket's srcloc lines and everything a person reads are
             ;; 1-based, and so is the port's.
             (add1 (token-line tok))
             (canonical-column (token-column tok))
             (escape-text (if (string? raw) raw (format "~a" raw)))
             (case name
               [(literal) (canonical-datum (token-e tok))]
               [else "-"])))
  (get-output-string out))

(module+ main
  (define args (current-command-line-arguments))
  (when (zero? (vector-length args))
    (eprintf "usage: tokens.rkt FILE\n")
    (exit 1))
  (display (dump-tokens (file->string (vector-ref args 0)))))

(provide dump-tokens)
