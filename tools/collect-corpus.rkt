#lang racket/base
;; Copies the corpus out of the reference checkout into `test/corpus/`.
;;
;; Committing the result is what makes the differential suite hermetic: CI runs
;; it with neither Racket nor the checkout present. This runs rarely -- only
;; when the reference pin moves -- and the diff it produces is the review
;; artifact for that move.
;;
;;   racket tools/collect-corpus.rkt        (or: just corpus)
(require racket/file racket/path racket/string racket/list
         (prefix-in in: (file "../reference/shrubbery/shrubbery/tests/input.rkt")))

(define corpus "test/corpus")
(define reference "reference")

(define (write-case bucket name text)
  (define dir (build-path corpus bucket))
  (make-directory* dir)
  (call-with-output-file (build-path dir (string-append name ".shrub"))
    #:exists 'replace
    (lambda (o) (write-string text o))))

;; The 12 inputs the reference's own parse suite runs on. `input1` is split into
;; parts in the source to keep an O(n^2) test tractable; it is one document.
(define spec-cases
  (list (cons "input1" in:input1)
        (cons "input1a" in:input1a)
        (cons "input1b" in:input1b)
        (cons "input2" in:input2)
        (cons "input3" in:input3)
        (cons "input3b" in:input3b)
        (cons "input4" in:input4)
        (cons "input5" in:input5)
        (cons "input6" in:input6)
        (cons "input7" in:input7)
        (cons "input8" in:input8)
        (cons "input9" in:input9)))

;; Hand-written coverage for what the corpus cannot reach. The .rhm files
;; contain no tabs at all, so nothing in them exercises the column partial
;; order or reaches the incomparable case.
(define tab-cases
  (list (cons "tab-indent" "a:\n\tb\n\tc\n")
        (cons "tab-then-space" "a:\n\t b\n\t c\n")
        (cons "space-then-tab" "a:\n \tb\n \tc\n")
        (cons "tab-continue" "a:\n\tb\n\t+ c\n")
        (cons "tab-bar" "a\n\t| b\n\t| c\n")
        (cons "mixed-incomparable" "a:\n \tb\n  \tc\n")
        (cons "tab-inside-parens" "f(\n\ta,\n\tb)\n")
        (cons "tab-only-line" "a:\n\t\tb\n")))

;; A `.rhm` file whose `#lang` is not a Rhombus dialect is not shrubbery
;; notation -- `rhombus-lib/rhombus/main.rhm` is `racket/base`, named `.rhm` so
;; that the reader can point at it. Including it would put a file the reference
;; itself cannot lex into a corpus whose whole purpose is comparing how the two
;; implementations lex.
(define (shrubbery-source? p)
  (define text (file->string p))
  (regexp-match? #rx"^#lang +(rhombus|shrubbery|at-exp +rhombus)" text))

(define (rhm-files)
  (for/list ([p (in-directory reference)]
             #:when (and (path-has-extension? p #".rhm")
                         (not (regexp-match? #rx"[.]git/" (path->string p)))
                         (shrubbery-source? p)))
    p))

;; Flatten `a/b/c.rhm` to `a__b__c.rhm` so the corpus is one flat directory and
;; a filter pattern reads like a path.
(define (strip-lang name)
  (regexp-replace #rx"[.]rhm$" name ""))

(define (drop-lang-line text)
  (if (regexp-match? #rx"^#lang " text)
      (let ([i (for/first ([j (in-range (string-length text))]
                           #:when (char=? #\newline (string-ref text j)))
                 j)])
        (if i (substring text (add1 i)) ""))
      text))

(define (flat-name p)
  (define rel (find-relative-path (path->complete-path reference)
                                  (path->complete-path p)))
  (string-replace (path->string rel) "/" "__"))

(define (main)
  (make-directory* corpus)
  (for ([c (in-list spec-cases)]) (write-case "spec" (car c) (cdr c)))
  (for ([c (in-list tab-cases)]) (write-case "tabs" (car c) (cdr c)))
  (define rhm (rhm-files))
  (make-directory* (build-path corpus "rhm"))
  ;; A `.rhm` file has a `#lang` line the host reader consumes before shrubbery
  ;; ever sees it. Stripping it here means both implementations read exactly the
  ;; same bytes, rather than each being trusted to strip it the same way.
  (for ([p (in-list rhm)])
    (write-case "rhm" (strip-lang (flat-name p)) (drop-lang-line (file->string p))))
  (call-with-output-file (build-path corpus "manifest.json") #:exists 'replace
    (lambda (o)
      (fprintf o "{\n")
      (fprintf o "  \"_comment\": \"Provenance for every corpus file. Regenerate with `just corpus`. Committed so the differential suite runs without the reference checkout.\",\n")
      (fprintf o "  \"counts\": { \"spec\": ~a, \"tabs\": ~a, \"rhm\": ~a },\n"
               (length spec-cases) (length tab-cases) (length rhm))
      (fprintf o "  \"origin\": {\n")
      (fprintf o "    \"spec\": \"shrubbery/shrubbery/tests/input.rkt\",\n")
      (fprintf o "    \"tabs\": \"hand-written; the .rhm corpus contains no tabs\",\n")
      (fprintf o "    \"rhm\": \"every .rhm file in the reference checkout\"\n")
      (fprintf o "  }\n}\n")))
  (printf "spec: ~a, tabs: ~a, rhm: ~a\n" (length spec-cases) (length tab-cases) (length rhm)))

(main)
