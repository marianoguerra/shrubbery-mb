#lang racket/base
;; Records what the reference answers for every corpus file, into
;; `test/golden/`.
;;
;; Batch, in one process, on purpose: Racket starts in about 300 ms and there
;; are 632 corpus files. Spawning a process per file would turn a five-second
;; regeneration into a four-minute one, and a slow step is one that stops
;; getting run.
;;
;;   racket tools/oracle/collect-goldens.rkt        (or: just goldens)
(require racket/file racket/path racket/string racket/list file/sha1
         "tokens.rkt")

(define corpus "test/corpus")
(define golden "test/golden")

(define (corpus-files)
  (sort
   (for/list ([p (in-directory corpus)]
              #:when (path-has-extension? p #".shrub"))
     p)
   string<? #:key path->string))

;; A `.rhm` file is shrubbery notation with a `#lang` line on top. The reader
;; consumes that line before shrubbery ever sees it, so the corpus entry is
;; everything after it.
;; Corpus files are already pure shrubbery -- `just corpus` strips the `#lang`
;; line -- so both implementations read exactly the same bytes.
(define (source-of p) (file->string p))

(define (main)
  (define files (corpus-files))
  (define ok 0)
  (define failed '())
  (define hashes '())
  (for ([p (in-list files)])
    (define rel (path->string (find-relative-path (path->complete-path corpus)
                                                  (path->complete-path p))))
    (with-handlers ([exn:fail?
                     (lambda (e)
                       (set! failed (cons (cons rel (exn-message e)) failed)))])
      (define text (dump-tokens (source-of p)))
      (set! hashes (cons (cons rel (sha1 (open-input-string text))) hashes))
      ;; Full goldens for the buckets a person reads when something breaks; a
      ;; digest for the 610-file real-world bucket, which would otherwise be
      ;; 26 MB of committed intermediate artifact. A digest is enough to DETECT
      ;; a divergence, which is what CI needs; `just golden-for FILE` recreates
      ;; the full answer for the one file that diverged, which is what a person
      ;; needs.
      (when (or (string-prefix? rel "spec/") (string-prefix? rel "tabs/"))
        (define out (build-path golden (path-replace-extension rel #".tokens")))
        (make-directory* (path-only out))
        (call-with-output-file out #:exists 'replace
          (lambda (o) (write-string text o))))
      (set! ok (add1 ok))))
  (make-directory* golden)
  (call-with-output-file (build-path golden "tokens.index") #:exists 'replace
    (lambda (o)
      (fprintf o "# sha1 of the reference's token dump, one line per corpus file.\n")
      (fprintf o "# Regenerate with `just goldens`; a diff here is a behaviour change.\n")
      (for ([h (in-list (sort (reverse hashes) string<? #:key car))])
        (fprintf o "~a  ~a\n" (cdr h) (car h)))))
  (call-with-output-file (build-path golden "lex-failures.txt") #:exists 'replace
    (lambda (o)
      (for ([f (in-list (sort (reverse failed) string<? #:key car))])
        (fprintf o "~a\t~a\n" (car f) (string-replace (cdr f) "\n" " ")))))
  (printf "tokens: ~a hashed, ~a full goldens, ~a failed\n"
          ok
          (length (filter (lambda (h) (or (string-prefix? (car h) "spec/")
                                          (string-prefix? (car h) "tabs/")))
                          hashes))
          (length failed))
  (for ([f (in-list (reverse failed))])
    (printf "  ~a: ~a\n" (car f) (string-replace (cdr f) "\n" " "))))

(main)
