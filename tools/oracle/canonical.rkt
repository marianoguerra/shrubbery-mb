#lang racket/base
;; The canonical text form used to compare our answers with the reference's.
;;
;; Deliberately not Racket's `write`. Reproducing Racket's flonum printing byte
;; for byte is a real piece of work -- shortest-round-trip digits, the forced
;; `.0`, the exponent thresholds -- and a mismatch there would surface as a
;; parse-parity failure that is really a formatting bug. Writing the bits
;; instead removes the question. The MoonBit side of this lives in
;; `lib/sexp/datum.mbt`, and the two have to be read together.
(provide canonical-datum canonical-column escape-text)

(define (escape-into out s)
  (for ([ch (in-string s)])
    (define u (char->integer ch))
    (cond
      [(or (char=? ch #\\) (char=? ch #\") (char=? ch #\|))
       (write-char #\\ out) (write-char ch out)]
      [(and (>= u #x20) (< u #x7F)) (write-char ch out)]
      [else (fprintf out "\\u{~x}" u)])))

(define (escape-text s)
  (define out (open-output-string))
  (write-char #\" out)
  (escape-into out s)
  (write-char #\" out)
  (get-output-string out))

(define (flo->canonical d)
  (cond
    ;; Every NaN is the same value here, and the two implementations differ in
    ;; the payload bits.
    [(not (= d d)) "#f64:nan"]
    [else
     (define bs (real->floating-point-bytes d 8 #t))
     (define n (for/fold ([n 0]) ([b (in-bytes bs)]) (+ (* n 256) b)))
     (format "#f64:~a" (~hex n 16))]))

(define (~hex n width)
  (define s (number->string n 16))
  (string-append (make-string (max 0 (- width (string-length s))) #\0) s))

(define (canonical-datum v)
  (define out (open-output-string))
  (let loop ([v v])
    (cond
      [(symbol? v) (write-char #\| out) (escape-into out (symbol->string v)) (write-char #\| out)]
      [(keyword? v) (write-string "#:|" out) (escape-into out (keyword->string v)) (write-char #\| out)]
      [(string? v) (write-char #\" out) (escape-into out v) (write-char #\" out)]
      [(bytes? v)
       (write-string "#\"" out)
       (for ([b (in-bytes v)]) (fprintf out "\\x~a" (~hex b 2)))
       (write-char #\" out)]
      [(char? v) (fprintf out "#\\u{~x}" (char->integer v))]
      [(boolean? v) (write-string (if v "#t" "#f") out)]
      [(void? v) (write-string "#<void>" out)]
      ;; `exact?` demands a number, so the number test has to come first: a
      ;; `#{...}` escape can hold a regexp or a syntax object, and asking
      ;; whether those are exact is a contract violation rather than a #f.
      [(and (number? v) (exact? v) (integer? v)) (write-string (number->string v) out)]
      [(and (number? v) (exact? v) (rational? v))
       (fprintf out "~a/~a" (numerator v) (denominator v))]
      [(flonum? v) (write-string (flo->canonical v) out)]
      [(syntax? v) (write-string "#<syntax>" out) (loop (syntax->datum v))]
      [(regexp? v) (fprintf out "#<rx:~a>" (escape-text (object-name v)))]
      [(null? v) (write-string "()" out)]
      [(pair? v)
       (write-char #\( out) (loop (car v)) (write-string " . " out) (loop (cdr v)) (write-char #\) out)]
      [(vector? v)
       (write-string "#(" out)
       (for ([x (in-vector v)] [i (in-naturals)])
         (unless (zero? i) (write-char #\space out))
         (loop x))
       (write-char #\) out)]
      [else (fprintf out "#<other:~s>" v)]))
  (get-output-string out))

;; The same shape `Column::to_display` produces on the MoonBit side: a plain
;; count, `.5` for the `|` half, and `+Ntab+` where a tab starts a new run.
;; Racket stores the runs rightmost-first, so they are reversed here.
(define (canonical-column col)
  (define runs (if (number? col) (list col) (reverse col)))
  (define out (open-output-string))
  (for ([v (in-list runs)] [i (in-naturals)])
    (cond
      [(odd? i) (fprintf out "+~atab+" (inexact->exact (floor v)))]
      [else
       (fprintf out "~a" (inexact->exact (floor v)))
       (when (not (integer? v)) (write-string ".5" out))]))
  (get-output-string out))
