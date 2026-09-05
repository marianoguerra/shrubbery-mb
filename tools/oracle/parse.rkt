#lang racket/base
;; Dump the reference's parse of a file, in the canonical form
;; `@ast.Node::canonical` produces.
;;
;;   racket tools/oracle/parse.rkt FILE
;;
;; A file the reference rejects prints `!error <message>` instead, so that the
;; error oracle and the parse oracle can share one golden.
(require racket/file racket/string racket/port
         shrubbery/parse
         "canonical.rkt")

(provide dump-parse)

(define tags '(multi group block alts parens brackets braces quotes))

(define (write-shrub v out)
  (cond
    [(and (pair? v) (eq? 'op (car v)))
     (fprintf out "(op ~a)" (canonical-datum (cadr v)))]
    [(and (pair? v) (memq (car v) tags))
     (fprintf out "(~a" (car v))
     (for ([e (in-list (cdr v))])
       (write-char #\space out)
       (write-shrub e out))
     (write-char #\) out)]
    [(and (pair? v) (eq? 'parsed (car v)))
     (fprintf out "(parsed ~a)" (canonical-datum (cadr v)))]
    [else (write-string (canonical-datum v) out)]))

(define (dump-parse src)
  (define out (open-output-string))
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (fprintf out "!error ~a\n"
                              (let ([m (exn-message e)])
                                ;; Drop the `srcloc: ` prefix the reader adds;
                                ;; the message itself is what is compared.
                                (string-join (cdr (string-split m ": ")) ": "))))])
    (define in (open-input-string src))
    ;; Line counting must be ON. Without it `syntax-column` is #f for every
    ;; token, and the de-indentation of `@` text -- which measures a line's
    ;; indentation as its leading whitespace PLUS the column it starts at --
    ;; silently uses 0 for the second half. A `#lang shrubbery` file is read
    ;; through a counting port, so an oracle that does not count is measuring
    ;; something the reader never does.
    (port-count-lines! in)
    (define stx (parse-all in))
    (write-shrub (syntax->datum stx) out)
    (write-char #\newline out))
  (get-output-string out))

(module+ main
  (define args (current-command-line-arguments))
  (when (zero? (vector-length args))
    (eprintf "usage: parse.rkt FILE\n")
    (exit 1))
  (display (dump-parse (file->string (vector-ref args 0)))))
