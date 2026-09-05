#lang racket/base
;; Generates `lib/unicode/tables/tables.mbt`.
;;
;; The tables are derived from THE REFERENCE'S OWN ANSWERS, not from a Unicode
;; release: `char-alphabetic?` and friends are swept over the whole code-point
;; space, and the emoji table is expanded out of the reference's own generated
;; `private/emoji.rkt`. That is agreement by construction. Deriving them from a
;; UCD download instead would be agreement by hope, and the hope is
;; version-shaped -- the two implementations would sooner or later disagree
;; about which identifiers are legal, on inputs nobody has.
;;
;; Note also that Racket's `char-alphabetic?` is the Unicode ALPHABETIC PROPERTY,
;; not the L* general categories; a hand-rolled table would get that wrong.
;;
;;   racket tools/gen-unicode-tables.rkt        (or: just unicode-regen)

(require racket/list racket/string racket/format)

(define out-path "lib/unicode/tables/tables.mbt")
(define emoji-path "reference/shrubbery-lib/shrubbery/private/emoji.rkt")
(define max-code #x10FFFF)

;; ---------------------------------------------------------------------------
;; Category sweeps

(define (surrogate? i) (and (>= i #xD800) (<= i #xDFFF)))

;; Ranges of code points satisfying `pred`, as a flat list (lo hi lo hi ...).
(define (sweep pred)
  (define out '())
  (let loop ([i 0] [start #f])
    (cond
      [(> i max-code)
       (when start (set! out (cons (cons start (sub1 i)) out)))]
      [else
       (define ok (and (not (surrogate? i)) (pred (integer->char i))))
       (cond
         [(and ok (not start)) (loop (add1 i) i)]
         [(and (not ok) start)
          (set! out (cons (cons start (sub1 i)) out))
          (loop (add1 i) #f)]
         [else (loop (add1 i) start)])]))
  (append* (map (lambda (p) (list (car p) (cdr p))) (reverse out))))

;; ---------------------------------------------------------------------------
;; Emoji, expanded out of the reference's own table

(define (read-forms path)
  (with-input-from-file path
    (lambda ()
      (read-line)
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
    [else (error 'expand "unexpected regexp form ~s" e)]))

(define (abbrev-strings name)
  (define forms (read-forms emoji-path))
  (define abbrevs
    (findf (lambda (f) (and (pair? f) (eq? (car f) 'define-lex-abbrevs))) forms))
  (define clause (assq name (cdr abbrevs)))
  (unless clause (error 'abbrev-strings "no ~a in ~a" name emoji-path))
  (filter (lambda (s) (> (string-length s) 0))
          (remove-duplicates (expand (cadr clause)))))

;; A trie over code-point sequences, flattened into two integer arrays.
;;
;; `nodes` holds [first-edge, edge-count, terminal] per node and `edges` holds
;; [code-point, target] per edge, sorted by code point within a node so the
;; scanner can stop early. Flat arrays rather than a node struct for the same
;; reason the range tables are flat: this is looked up once per identifier
;; character and allocating on that path would be felt.
(struct tnode (children [terminal #:mutable]) #:transparent)

(define (build-trie seqs)
  (define root (tnode (make-hasheqv) #f))
  (for ([s (in-list seqs)])
    (define n
      (for/fold ([n root]) ([ch (in-string s)])
        (define k (char->integer ch))
        (or (hash-ref (tnode-children n) k #f)
            (let ([fresh (tnode (make-hasheqv) #f)])
              (hash-set! (tnode-children n) k fresh)
              fresh))))
    (set-tnode-terminal! n #t))
  root)

;; Breadth-first so a node's edges are contiguous and the arrays stay small.
(define (flatten-trie root)
  (define nodes '())
  (define edges '())
  (define order (list root))
  (define index (make-hasheq (list (cons root 0))))
  (let loop ([queue order])
    (cond
      [(null? queue) (void)]
      [else
       (define n (car queue))
       (define kids (sort (hash->list (tnode-children n)) < #:key car))
       (define rest
         (for/fold ([q (cdr queue)]) ([kv (in-list kids)])
           (hash-set! index (cdr kv) (hash-count index))
           (append q (list (cdr kv)))))
       (set! nodes (cons (list n kids) nodes))
       (loop rest)]))
  (set! nodes (reverse nodes))
  ;; Second pass: now every node has an index, so edges can name their targets.
  (define node-out '())
  (for ([entry (in-list nodes)])
    (define kids (cadr entry))
    (define first-edge (quotient (length edges) 2))
    (for ([kv (in-list kids)])
      (set! edges (append edges (list (car kv) (hash-ref index (cdr kv))))))
    (set! node-out
          (append node-out
                  (list first-edge (length kids)
                        (if (tnode-terminal (car entry)) 1 0)))))
  (values node-out edges))

;; ---------------------------------------------------------------------------
;; Emit

(define (ints->rows xs per)
  (for/list ([chunk (in-list (chunk xs per))])
    (string-append "  " (string-join (map number->string chunk) ", ") ",")))

(define (chunk xs n)
  (if (null? xs) '() (cons (take xs (min n (length xs))) (chunk (drop xs (min n (length xs))) n))))

(define (emit-table port name doc xs per)
  (fprintf port "///|\n")
  (for ([l (in-list (string-split doc "\n"))]) (fprintf port "/// ~a\n" l))
  (fprintf port "pub let ~a : FixedArray[Int] = [\n" name)
  (for ([row (in-list (ints->rows xs per))]) (fprintf port "~a\n" row))
  (fprintf port "]\n\n"))

(define (main)
  (define one-char (abbrev-strings 'one-char-emoji))
  (define seqs (abbrev-strings 'emoji))
  (define-values (nodes edges) (flatten-trie (build-trie seqs)))
  (define one-char-points
    (sort (map (lambda (s) (char->integer (string-ref s 0))) one-char) <))
  (define one-char-ranges
    (let loop ([ps one-char-points] [start #f] [prev #f] [acc '()])
      (cond
        [(null? ps)
         (reverse (if start (cons (list start prev) acc) acc))]
        [(and prev (= (car ps) (add1 prev))) (loop (cdr ps) start (car ps) acc)]
        [start (loop (cdr ps) (car ps) (car ps) (cons (list start prev) acc))]
        [else (loop (cdr ps) (car ps) (car ps) acc)])))
  (call-with-output-file out-path #:exists 'replace
    (lambda (o)
      (fprintf o "// Generated by tools/gen-unicode-tables.rkt from Racket ~a\n" (version))
      (fprintf o "// and the reference's private/emoji.rkt. DON'T EDIT IT --\n")
      (fprintf o "// run `just unicode-regen` and review the diff.\n\n")
      (emit-table o "alphabetic"
                  "Racket's `char-alphabetic?`: the Unicode Alphabetic property,\nwhich is NOT the same as the L* general categories."
                  (sweep char-alphabetic?) 12)
      (emit-table o "numeric" "Racket's `char-numeric?`." (sweep char-numeric?) 12)
      (emit-table o "symbolic" "Racket's `char-symbolic?` (Sm, Sc, Sk, So)."
                  (sweep char-symbolic?) 12)
      (emit-table o "punctuation"
                  "Racket's `char-punctuation?` (Pc, Pd, Ps, Pe, Pi, Pf, Po)."
                  (sweep char-punctuation?) 12)
      (emit-table o "whitespace" "Racket's `char-whitespace?`."
                  (sweep char-whitespace?) 12)
      (emit-table o "one_char_emoji"
                  (format "The ~a single-code-point emoji. These are identifier\ncharacters, and are excluded from the operator characters."
                          (length one-char-points))
                  (append* (map (lambda (r) (list (car r) (cadr r))) one-char-ranges)) 12)
      (emit-table o "emoji_nodes"
                  (format "Emoji-sequence trie, ~a sequences: [first_edge, edge_count,\nterminal] per node. Node 0 is the root."
                          (length seqs))
                  nodes 12)
      (emit-table o "emoji_edges"
                  "Emoji-sequence trie: [code_point, target_node] per edge,\nsorted by code point within each node."
                  edges 12)))
  (printf "~a: ~a alphabetic ranges, ~a emoji sequences, ~a trie nodes\n"
          out-path
          (quotient (length (sweep char-alphabetic?)) 2)
          (length seqs)
          (quotient (length nodes) 3)))

(main)
