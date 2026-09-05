#lang racket/base
;; What the reference PRINTS for a file, in each of the modes its own test
;; suite exercises.
;;
;; Every mode on one line, prefixed by its name, so that one golden covers all
;; of them and a divergence names the mode it happened in.
(require racket/file racket/port racket/string
         shrubbery/parse shrubbery/write)

(provide dump-print print-modes)

;; The modes, in the order the reference's `check-reparse` runs them. `width`
;; #f means "always take the single-line branch"; 0 means "take every break".
(define print-modes
  (list (list "flat"            #f #f #f #f)
        (list "pretty"          #t #f #f #f)
        (list "pretty-0"        #t #f #f 0)
        (list "pretty-40"       #t #f #f 40)
        (list "armor"           #t #t #f #f)
        (list "armor-0"         #t #t #f 0)
        (list "armor-40"        #t #t #f 40)
        (list "multi"           #t #f #t #f)
        (list "multi-0"         #t #f #t 0)
        (list "multi-40"        #t #f #t 40)
        (list "pretty-120"      #t #f #f 120)))

(define (dump-print src)
  (define out (open-output-string))
  (with-handlers ([exn:fail? (lambda (e) (write-string "!error\n" out))])
    (define in (open-input-string src))
    (port-count-lines! in)
    (define v (syntax->datum (parse-all in)))
    (for ([m (in-list print-modes)])
      (define-values (name pretty? armor? multi? width)
        (values (car m) (cadr m) (caddr m) (cadddr m) (list-ref m 4)))
      (define s (with-output-to-string
                  (lambda ()
                    (write-shrubbery v (current-output-port)
                                     #:pretty? pretty?
                                     #:armor? armor?
                                     #:prefer-multiline? multi?
                                     #:width width))))
      ;; One record per mode, with the newlines escaped so a record is a line.
      (fprintf out "~a\t~a\n" name (escape-lines s))))
  (get-output-string out))

(define (escape-lines s)
  (define out (open-output-string))
  (for ([ch (in-string s)])
    (case ch
      [(#\newline) (write-string "\\n" out)]
      [(#\return) (write-string "\\r" out)]
      [(#\tab) (write-string "\\t" out)]
      [(#\\) (write-string "\\\\" out)]
      [else (write-char ch out)]))
  (get-output-string out))

(module+ main
  (define args (current-command-line-arguments))
  (display (dump-print (file->string (vector-ref args 0)))))
