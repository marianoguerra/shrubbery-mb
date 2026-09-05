#lang racket/base
;; Generates `lib/unicode/parity_test.mbt`.
;;
;; The category tables are generated FROM Racket, so their contents agree with
;; the reference by construction and testing the data would be circular. What is
;; NOT true by construction is the lookup: a binary search over a flat
;; [lo, hi, lo, hi, ...] array is exactly the kind of code that is off by one at
;; a boundary and right everywhere else. So the probes are the boundaries --
;; lo-1, lo, hi, hi+1 for every range in every table -- with Racket's own answer
;; recorded beside each.
;;
;; The emoji and grapheme probes are different in kind: those ARE checking data,
;; because the trie is a transformation of the reference's table and the
;; grapheme segmenter is a third-party package on a possibly different Unicode
;; version.
;;
;;   racket tools/gen-unicode-tests.rkt        (or: just unicode-regen)

(require racket/list racket/string racket/set)

(define out-path "lib/unicode/parity_test.mbt")
(define emoji-path "reference/shrubbery-lib/shrubbery/private/emoji.rkt")
(define max-code #x10FFFF)

(define (surrogate? i) (and (>= i #xD800) (<= i #xDFFF)))
(define (ok? pred i)
  (and (>= i 0) (<= i max-code) (not (surrogate? i)) (pred (integer->char i)) #t))

(define (ranges pred)
  (define out '())
  (let loop ([i 0] [start #f])
    (cond
      [(> i max-code) (when start (set! out (cons (cons start (sub1 i)) out)))]
      [else
       (define v (ok? pred i))
       (cond
         [(and v (not start)) (loop (add1 i) i)]
         [(and (not v) start)
          (set! out (cons (cons start (sub1 i)) out))
          (loop (add1 i) #f)]
         [else (loop (add1 i) start)])]))
  (reverse out))

(define (boundary-probes pred)
  (define rs (ranges pred))
  (define cps
    (sort (set->list
           (list->set
            (append* (for/list ([r (in-list rs)])
                       (list (sub1 (car r)) (car r) (cdr r) (add1 (cdr r)))))))
          <))
  (for/list ([cp (in-list cps)]
             #:when (and (>= cp 0) (<= cp max-code) (not (surrogate? cp))))
    (list cp (if (ok? pred cp) 1 0))))

(define (chunkify xs n)
  (if (null? xs) '()
      (cons (take xs (min n (length xs))) (chunkify (drop xs (min n (length xs))) n))))

(define (emit-probes o name doc probes)
  (fprintf o "///|\n")
  (for ([l (in-list (string-split doc "\n"))]) (fprintf o "/// ~a\n" l))
  (fprintf o "let ~a : FixedArray[Int] = [\n" name)
  (for ([chunk (in-list (chunkify (append* probes) 16))])
    (fprintf o "  ~a,\n" (string-join (map number->string chunk) ", ")))
  (fprintf o "]\n\n"))

(define (read-forms path)
  (with-input-from-file path
    (lambda () (read-line)
      (let loop ([acc '()])
        (define v (read))
        (if (eof-object? v) (reverse acc) (loop (cons v acc)))))))

(define (expand e)
  (cond
    [(string? e) (list e)]
    [(and (pair? e) (eq? (car e) ':or)) (append-map expand (cdr e))]
    [(and (pair? e) (eq? (car e) '::))
     (for/fold ([acc (list "")]) ([sub (in-list (cdr e))])
       (define parts (expand sub))
       (for*/list ([a (in-list acc)] [b (in-list parts)]) (string-append a b)))]
    [else (error 'expand "unexpected ~s" e)]))

(define (abbrev name)
  (define abbrevs
    (findf (lambda (f) (and (pair? f) (eq? (car f) 'define-lex-abbrevs)))
           (read-forms emoji-path)))
  (filter (lambda (s) (> (string-length s) 0))
          (remove-duplicates (expand (cadr (assq name (cdr abbrevs)))))))

(define (utf16-length s)
  (for/sum ([ch (in-string s)]) (if (> (char->integer ch) #xFFFF) 2 1)))

(define (mbt-string s)
  (string-append "\""
                 (apply string-append
                        (for/list ([ch (in-string s)])
                          (format "\\u{~x}" (char->integer ch))))
                 "\""))

(define (emit-string-int-table o name doc rows)
  (fprintf o "///|\n")
  (for ([l (in-list (string-split doc "\n"))]) (fprintf o "/// ~a\n" l))
  (fprintf o "let ~a : Array[(String, Int)] = [\n" name)
  (for ([r (in-list rows)])
    (fprintf o "  (~a, ~a),\n" (mbt-string (car r)) (cadr r)))
  (fprintf o "]\n\n"))

(define (rotate-sample xs n)
  ;; Reproducible: every 17th, wrapping. A random sample would churn the
  ;; generated file on every run for no reason.
  (define v (list->vector xs))
  (define len (vector-length v))
  (for/list ([i (in-range (min n len))]) (vector-ref v (modulo (* i 17) len))))

(define (grapheme-stress seqs)
  ;; Every emoji sequence is a grapheme-cluster stress case by construction --
  ;; ZWJ joins, skin-tone modifiers, variation selectors and flag pairs are
  ;; exactly the rules that separate UAX #29 from "one code point, one cluster".
  ;; The hand-written cases cover the families the emoji table does not reach.
  (append
   (list "abc"
         "a\u0301"
         "e\u0301\u0302\u0303"
         "\u1100\u1161\u11A8"
         "\uAC00"
         "\U0001F1E6\U0001F1E7"
         "\U0001F1E6\U0001F1E7\U0001F1E8"
         "\r\n"
         "\r"
         "\n"
         "a\r\nb"
         "\U0001F468\u200D\U0001F469\u200D\U0001F466"
         "x\uFE0F"
         "\t")
   (rotate-sample seqs 200)))

(define (main)
  (define seqs (abbrev 'emoji))
  (define one-char (abbrev 'one-char-emoji))
  (call-with-output-file out-path #:exists 'replace
    (lambda (o)
      (fprintf o "// Generated by tools/gen-unicode-tests.rkt from Racket ~a\n" (version))
      (fprintf o "// and the reference's private/emoji.rkt. DON'T EDIT IT --\n")
      (fprintf o "// run `just unicode-regen` and review the diff.\n\n")
      (emit-probes o "alphabetic_probes"
                   "[code point, expected] at every range boundary and one past it."
                   (boundary-probes char-alphabetic?))
      (emit-probes o "numeric_probes" "[code point, expected]."
                   (boundary-probes char-numeric?))
      (emit-probes o "symbolic_probes" "[code point, expected]."
                   (boundary-probes char-symbolic?))
      (emit-probes o "punctuation_probes" "[code point, expected]."
                   (boundary-probes char-punctuation?))
      (emit-probes o "whitespace_probes" "[code point, expected]."
                   (boundary-probes char-whitespace?))
      (emit-string-int-table
       o "emoji_probes"
       (format "Every one of the ~a emoji sequences, with its length in UTF-16\ncode units. The trie must return the LONGEST match for each."
               (length seqs))
       (for/list ([s (in-list seqs)]) (list s (utf16-length s))))
      (emit-string-int-table
       o "one_char_emoji_probes"
       (format "The ~a single-code-point emoji." (length one-char))
       (for/list ([s (in-list one-char)]) (list s (utf16-length s))))
      (emit-string-int-table
       o "grapheme_probes"
       "Racket's own `string-grapheme-count`. This one is checking DATA, not\nlookup: the segmenter is a third-party package whose tables may be on a\ndifferent Unicode version than the reference's."
       (for/list ([s (in-list (grapheme-stress seqs))])
         (list s (string-grapheme-count s))))
      (fprintf o "///|\n")
      (fprintf o "/// Walk a `[code point, expected]` probe table.\n")
      (fprintf o "fn check_probes(\n")
      (fprintf o "  name : String,\n  probes : FixedArray[Int],\n  pred : (Char) -> Bool,\n) -> Unit raise {\n")
      (fprintf o "  for i in 0..<(probes.length() / 2) {\n")
      (fprintf o "    let cp = probes[i * 2]\n")
      (fprintf o "    let want = probes[i * 2 + 1] == 1\n")
      (fprintf o "    if pred(cp.unsafe_to_char()) != want {\n")
      (fprintf o "      fail(\"\\{name}: U+\\{cp} should be \\{want}\")\n")
      (fprintf o "    }\n  }\n}\n\n")
      (for ([nm (in-list '("alphabetic" "numeric" "symbolic" "punctuation" "whitespace"))])
        (fprintf o "///|\n")
        (fprintf o "test \"~a agrees with Racket at every range boundary\" {\n" nm)
        (fprintf o "  check_probes(\"~a\", ~a_probes, @unicode.is_~a)\n}\n\n" nm nm nm))
      (fprintf o "///|\n")
      (fprintf o "test \"every emoji sequence is matched at its full length\" {\n")
      (fprintf o "  for probe in emoji_probes {\n")
      (fprintf o "    let (s, want) = probe\n")
      (fprintf o "    let got = @unicode.emoji_sequence_at(s, 0)\n")
      (fprintf o "    if got != want {\n")
      (fprintf o "      fail(\"emoji \\{s.escape()}: want \\{want} code units, got \\{got}\")\n")
      (fprintf o "    }\n  }\n}\n\n")
      (fprintf o "///|\n")
      (fprintf o "test \"single-code-point emoji are recognised as such\" {\n")
      (fprintf o "  for probe in one_char_emoji_probes {\n")
      (fprintf o "    let (s, _) = probe\n")
      (fprintf o "    if !@unicode.is_one_char_emoji(s.get_char(0).unwrap()) {\n")
      (fprintf o "      fail(\"one-char emoji \\{s.escape()} not recognised\")\n")
      (fprintf o "    }\n  }\n}\n\n")
      (fprintf o "///|\n")
      (fprintf o "test \"grapheme counts agree with Racket\" {\n")
      (fprintf o "  for probe in grapheme_probes {\n")
      (fprintf o "    let (s, want) = probe\n")
      (fprintf o "    let got = @unicode.grapheme_count(s)\n")
      (fprintf o "    if got != want {\n")
      (fprintf o "      fail(\"graphemes of \\{s.escape()}: want \\{want}, got \\{got}\")\n")
      (fprintf o "    }\n  }\n}\n")))
  (printf "~a written\n" out-path))

(main)
