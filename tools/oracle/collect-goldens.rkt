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
         "tokens.rkt"
         "parse.rkt"
         "print.rkt")

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

;; Which buckets carry the reference's FULL answer rather than a digest: the
;; ones a person reads when something breaks. The 610-file real-world bucket
;; would be 26 MB of committed intermediate artifact, and a digest detects a
;; divergence just as well.
(define (full-golden? rel)
  (or (string-prefix? rel "spec/")
      (string-prefix? rel "tabs/")
      (string-prefix? rel "fail/")))

(define (main)
  (define files (corpus-files))
  (define ok 0)
  (define failed '())
  (define hashes '())
  (define parse-hashes '())
  (define source-hashes '())
  (define print-hashes '())
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
      (when (full-golden? rel)
        (define out (build-path golden (path-replace-extension rel #".tokens")))
        (make-directory* (path-only out))
        (call-with-output-file out #:exists 'replace
          (lambda (o) (write-string text o))))
      (set! ok (add1 ok)))
    ;; The parse tree, as its own oracle. A file the reference REJECTS gets a
    ;; golden too -- `!error <message>` -- so that error parity is checked by
    ;; the same comparison rather than by a second one that could disagree.
    (define ptext (dump-parse (source-of p)))
    (set! parse-hashes (cons (cons rel (sha1 (open-input-string ptext))) parse-hashes))
    (when (full-golden? rel)
      (define pout (build-path golden (path-replace-extension rel #".sexp")))
      (make-directory* (path-only pout))
      (call-with-output-file pout #:exists 'replace
        (lambda (o) (write-string ptext o))))
    ;; And what it reproduces from that parse.
    (define stext (dump-source (source-of p)))
    (set! source-hashes (cons (cons rel (sha1 (open-input-string stext))) source-hashes))
    (when (full-golden? rel)
      (define sout (build-path golden (path-replace-extension rel #".source")))
      (make-directory* (path-only sout))
      (call-with-output-file sout #:exists 'replace
        (lambda (o) (write-string stext o))))
    ;; And what it prints, in every layout mode.
    (define wtext (dump-print (source-of p)))
    (set! print-hashes (cons (cons rel (sha1 (open-input-string wtext))) print-hashes))
    (when (full-golden? rel)
      (define wout (build-path golden (path-replace-extension rel #".print")))
      (make-directory* (path-only wout))
      (call-with-output-file wout #:exists 'replace
        (lambda (o) (write-string wtext o)))))
  (make-directory* golden)
  (call-with-output-file (build-path golden "tokens.index") #:exists 'replace
    (lambda (o)
      (fprintf o "# sha1 of the reference's token dump, one line per corpus file.\n")
      (fprintf o "# Regenerate with `just goldens`; a diff here is a behaviour change.\n")
      (for ([h (in-list (sort (reverse hashes) string<? #:key car))])
        (fprintf o "~a  ~a\n" (cdr h) (car h)))))
  (call-with-output-file (build-path golden "parse.index") #:exists 'replace
    (lambda (o)
      (fprintf o "# sha1 of the reference's parse, one line per corpus file.\n")
      (fprintf o "# Regenerate with `just goldens`; a diff here is a behaviour change.\n")
      (for ([h (in-list (sort (reverse parse-hashes) string<? #:key car))])
        (fprintf o "~a  ~a\n" (cdr h) (car h)))))
  (call-with-output-file (build-path golden "source.index") #:exists 'replace
    (lambda (o)
      (fprintf o "# sha1 of what the reference reproduces from its own parse.\n")
      (fprintf o "# Regenerate with `just goldens`; a diff here is a behaviour change.\n")
      (for ([h (in-list (sort (reverse source-hashes) string<? #:key car))])
        (fprintf o "~a  ~a\n" (cdr h) (car h)))))
  (call-with-output-file (build-path golden "print.index") #:exists 'replace
    (lambda (o)
      (fprintf o "# sha1 of what the reference prints, in all eleven layout modes.\n")
      (fprintf o "# Regenerate with `just goldens`; a diff here is a behaviour change.\n")
      (for ([h (in-list (sort (reverse print-hashes) string<? #:key car))])
        (fprintf o "~a  ~a\n" (cdr h) (car h)))))
  (call-with-output-file (build-path golden "lex-failures.txt") #:exists 'replace
    (lambda (o)
      (for ([f (in-list (sort (reverse failed) string<? #:key car))])
        (fprintf o "~a\t~a\n" (car f) (string-replace (cdr f) "\n" " ")))))
  (printf "tokens: ~a hashed, ~a full goldens, ~a failed\n"
          ok
          (length (filter (lambda (h) (full-golden? (car h))) hashes))
          (length failed))
  (for ([f (in-list (reverse failed))])
    (printf "  ~a: ~a\n" (car f) (string-replace (cdr f) "\n" " "))))

(main)
