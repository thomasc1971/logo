;; parser.lisp - Logo source reader
;;
;; Logo is not Lisp: it is a flat, arity-driven instruction stream
;; (`FD 100 RT 90 REPEAT 4 [FD 50 RT 90]`) with bracket lists, `:variables`,
;; `"strings"`, and `\` comments. Parsing therefore needs the primitive
;; arity table (primitives.lisp): after a command word we know exactly how
;; many argument expressions to consume.
;;
;; Two passes:
;;   1. scan for TO ... END to learn procedure names and arities (so a
;;      procedure can be called before its definition in the file);
;;   2. arity-driven recursive descent over the token vector.
;;
;; AST shapes:
;;   instruction: (cmd "FD" arg ...) | (to name params body)
;;                | (if cond body) | (ifelse cond then else)
;;                | (repeat count body) | (run body) | (make name value)
;;                | (thing name) | (output value) | (stop) | (local names)
;;   expression:  number | (:string S) | (:var NAME) | (:word NAME)
;;                | (:list (expr ...)) | (:call NAME (expr ...))
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-parser)

;; ---------------------------------------------------------------------------
;; Tokenizer
;; ---------------------------------------------------------------------------
(defun logo-tokenize (source)
  "Tokenize Logo SOURCE into a list of tokens:
   (:num VALUE) (:word NAME) (:var NAME) (:string S) (:lbracket) (:rbracket)"
  (let* ((len (length source)))
    (let loop ((i 0)
               (tokens nil))
      (if (>= i len)
        (reverse tokens)
        (let* ((c (string-ref source i)))
          (cond
            ((or (char=? c #\space) (char=? c #\tab) (char=? c #\newline)
                 (char=? c #\return))
             (loop (+ i 1) tokens))
            ((char=? c #\\)
             (let skip ((j i))
               (if (or (>= j len) (char=? (string-ref source j) #\newline))
                 (loop j tokens)
                 (skip (+ j 1)))))
            ((or (char=? c #\[) (char=? c #\())
             (loop (+ i 1) (cons '(:lbracket) tokens)))
            ((or (char=? c #\]) (char=? c #\)))
             (loop (+ i 1) (cons '(:rbracket) tokens)))
            ((char=? c #\:)
             (let scan ((j (+ i 1)))
               (if
                 (or (>= j len) (not (logo-word-char? (string-ref source j))))
                 (let* ((name (substring source (+ i 1) j)))
                   (loop j (cons (list ':var (string-upcase name)) tokens)))
                 (scan (+ j 1)))))
            ((char=? c #\")
             (let scan ((j (+ i 1)))
               (if (or (>= j len) (char=? (string-ref source j) #\"))
                 (let* ((text (substring source (+ i 1) j)))
                   (loop (min (+ j 1) len) (cons (list ':string text) tokens)))
                 (scan (+ j 1)))))
            ((or (char-numeric? c)
                 (and (char=? c #\-) (< (+ i 1) len)
                      (char-numeric? (string-ref source (+ i 1))))
                 (and (char=? c #\.) (< (+ i 1) len)
                      (char-numeric? (string-ref source (+ i 1)))))
             (let scan ((j i))
               (if
                 (or (>= j len)
                     (let* ((d (string-ref source j)))
                       (not
                        (or (char-numeric? d) (char=? d #\.) (char=? d #\-)))))
                 (let* ((text (substring source i j)))
                   (loop j (cons (list ':num (string->number text)) tokens)))
                 (scan (+ j 1)))))
            ((logo-word-start? c)
             (let scan ((j i))
               (if
                 (or (>= j len) (not (logo-word-char? (string-ref source j))))
                 (let* ((name (substring source i j)))
                   (loop j (cons (list ':word (string-upcase name)) tokens)))
                 (scan (+ j 1)))))
            (#t
             (error (format nil "unexpected character ~a in Logo source" c)))))))))

(defun logo-word-start? (c)
  "True if C can start a Logo word."
  (or (char-alphabetic? c) (char=? c #\_)))

(defun logo-word-char? (c)
  "True if C can continue a Logo word."
  (or (char-alphabetic? c) (char-numeric? c) (char=? c #\_) (char=? c #\?)
      (char=? c #\!)))

;; ---------------------------------------------------------------------------
;; Pass 1: collect procedure arities from TO ... END
;; ---------------------------------------------------------------------------
(defun logo-scan-procedures (tokens)
  "Scan TOKENS for TO definitions; return a hash NAME -> arity (params count)."
  (let* ((table (make-hash-table)))
    (let loop ((rest tokens))
      (if (null? rest)
        table
        (let* ((tok (car rest)))
          (if
            (and (eq? (car tok) ':word) (equal? (cadr tok) "TO")
                 (not (null? (cdr rest))) (eq? (car (cadr rest)) ':word))
            (let* ((name-tok (cadr rest))
                   (name (cadr name-tok))
                   (params nil)
                   (scan (cddr rest)))
              (let collect ((s scan))
                (if (and (not (null? s)) (eq? (car (car s)) ':var))
                  (progn (set! params (cons (cadr (car s)) params))
                    (collect (cdr s)))
                  (hash-set! table name (length params))))
              (loop (cdr rest)))
            (loop (cdr rest))))))))

;; ---------------------------------------------------------------------------
;; Pass 2: arity-driven parsing
;; ---------------------------------------------------------------------------
(defun logo-parse (source)
  "Parse Logo SOURCE into a list of instructions (AST).
   Returns an error object if parsing fails. NOTE: Ditty errors are values
   that propagate only through checked frames; every caller must test the
   result with error? before destructuring it (car/cdr on an error object
   produces a confusing secondary error). See logo-repl-eval."
  (let* ((tokens (logo-tokenize source))
         (procs (logo-scan-procedures tokens))
         (vec (list->vector tokens)))
    (let* ((parsed (logo-parse-program vec 0 (length tokens) procs)))
      (if (error? parsed) parsed (car parsed)))))

(defun list->vector (xs)
  "Convert list XS to a vector."
  (let* ((v (make-vector (length xs))))
    (let loop ((rest xs)
               (i 0))
      (if (null? rest)
        v
        (progn (vector-set! v i (car rest)) (loop (cdr rest) (+ i 1)))))))

(defun logo-parse-program (vec i end procs)
  "Parse instructions from VEC[I..END). Returns (instructions . next-index),
   or an error object on failure."
  (let loop ((i i)
             (instructions nil))
    (if (>= i end)
      (cons (reverse instructions) i)
      (let* ((parsed (logo-parse-instruction vec i end procs)))
        (if (error? parsed)
          parsed
          (loop (cdr parsed) (cons (car parsed) instructions)))))))

(defun logo-parse-instruction (vec i end procs)
  "Parse one instruction at VEC[I]. Returns (instruction . next-index)."
  (let* ((tok (vector-ref vec i)))
    (if (not (eq? (car tok) ':word))
      (error (format nil "expected a Logo command, got ~a" tok))
      (let* ((name (cadr tok)))
        (cond
          ((equal? name "END")
           (error "END without TO"))
          ((equal? name "TO")
           (logo-parse-to vec i end procs))
          ((equal? name "STOP")
           (cons '(stop) (+ i 1)))
          ((equal? name "OUTPUT")
           (let* ((parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? parsed)
               parsed
               (cons (list 'output (car parsed)) (cdr parsed)))))
          ((equal? name "IF")
           (let* ((cond-parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? cond-parsed)
               cond-parsed
               (let* ((body-parsed
                       (logo-parse-bracket-body vec (cdr cond-parsed) end procs)))
                 (if (error? body-parsed)
                   body-parsed
                   (cons (list 'if (car cond-parsed) (car body-parsed))
                    (cdr body-parsed)))))))
          ((equal? name "IFELSE")
           (let* ((cond-parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? cond-parsed)
               cond-parsed
               (let* ((then-parsed
                       (logo-parse-bracket-body vec (cdr cond-parsed) end procs)))
                 (if (error? then-parsed)
                   then-parsed
                   (let* ((else-parsed
                           (logo-parse-bracket-body vec (cdr then-parsed) end
                            procs)))
                     (if (error? else-parsed)
                       else-parsed
                       (cons
                        (list 'ifelse (car cond-parsed)
                         (car then-parsed) (car else-parsed))
                        (cdr else-parsed)))))))))
          ((equal? name "REPEAT")
           (let* ((count-parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? count-parsed)
               count-parsed
               (let* ((body-parsed
                       (logo-parse-bracket-body vec (cdr count-parsed) end
                        procs)))
                 (if (error? body-parsed)
                   body-parsed
                   (cons (list 'repeat (car count-parsed) (car body-parsed))
                    (cdr body-parsed)))))))
          ((equal? name "RUN")
           (let* ((body-parsed (logo-parse-bracket-body vec (+ i 1) end procs)))
             (if (error? body-parsed)
               body-parsed
               (cons (list 'run (car body-parsed)) (cdr body-parsed)))))
          ((equal? name "MAKE")
           (let* ((name-parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? name-parsed)
               name-parsed
               (let* ((value-parsed
                       (logo-parse-expr vec (cdr name-parsed) end procs)))
                 (if (error? value-parsed)
                   value-parsed
                   (cons (list 'make (car name-parsed) (car value-parsed))
                    (cdr value-parsed)))))))
          ((equal? name "THING")
           (let* ((parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? parsed)
               parsed
               (cons (list 'thing (car parsed)) (cdr parsed)))))
          ((equal? name "LOCAL")
           (let* ((parsed (logo-parse-expr vec (+ i 1) end procs)))
             (if (error? parsed)
               parsed
               (cons (list 'local (car parsed)) (cdr parsed)))))
          (#t
           (let* ((arity (or (logo-primitive-arity name) (hash-ref procs name))))
             (if (null? arity)
               (error (format nil "unknown Logo word: ~a" name))
               (let loop ((j (+ i 1))
                          (args nil)
                          (n arity))
                 (if (= n 0)
                   (cons (cons 'cmd (cons name (reverse args))) j)
                   (let* ((arg-parsed (logo-parse-expr vec j end procs)))
                     (if (error? arg-parsed)
                       arg-parsed
                       (loop (cdr arg-parsed)
                        (cons (car arg-parsed) args)
                        (- n 1))))))))))))))

(defun logo-parse-to (vec i end procs)
  "Parse TO NAME :params BODY END at VEC[I]. Returns (instruction . next)."
  (if (or (>= (+ i 1) end) (not (eq? (car (vector-ref vec (+ i 1))) ':word)))
    (error "TO without a procedure name")
    (logo-parse-to-name vec i end procs)))

(defun logo-parse-to-name (vec i end procs)
  "Parse TO ... END at VEC[I], given the name token exists. See logo-parse-to."
  (let* ((name (cadr (vector-ref vec (+ i 1))))
         (params nil)
         (j (+ i 2)))
    (let collect ((k j))
      (if (and (< k end) (eq? (car (vector-ref vec k)) ':var))
        (progn (set! params (cons (cadr (vector-ref vec k)) params))
          (collect (+ k 1)))
        (set! j k)))
    (let loop ((k j)
               (body nil))
      (if (>= k end)
        (error (format nil "TO ~a without END" name))
        (let* ((tok (vector-ref vec k)))
          (if (and (eq? (car tok) ':word) (equal? (cadr tok) "END"))
            (cons (list 'to name (reverse params) (reverse body)) (+ k 1))
            (let* ((parsed (logo-parse-instruction vec k end procs)))
              (if (error? parsed)
                parsed
                (loop (cdr parsed) (cons (car parsed) body))))))))))

(defun logo-parse-bracket-body (vec i end procs)
  "Parse [ instructions ] at VEC[I]. Returns (instructions . next-index)."
  (if (or (>= i end) (not (equal? (vector-ref vec i) '(:lbracket))))
    (error "expected [")
    (let loop ((k (+ i 1))
               (body nil))
      (if (>= k end)
        (error "unterminated [")
        (let* ((tok (vector-ref vec k)))
          (if (equal? tok '(:rbracket))
            (cons (reverse body) (+ k 1))
            (let* ((parsed (logo-parse-instruction vec k end procs)))
              (if (error? parsed)
                parsed
                (loop (cdr parsed) (cons (car parsed) body))))))))))

(defun logo-parse-expr (vec i end procs)
  "Parse one argument expression at VEC[I]. Returns (expr . next-index)."
  (if (>= i end)
    (error "unexpected end of Logo source; missing argument")
    (let* ((tok (vector-ref vec i)))
      (cond
        ((eq? (car tok) ':num)
         (cons (cadr tok) (+ i 1)))
        ((eq? (car tok) ':string)
         (cons (list ':string (cadr tok)) (+ i 1)))
        ((eq? (car tok) ':var)
         (cons (list ':var (cadr tok)) (+ i 1)))
        ((equal? tok '(:lbracket))
         (logo-parse-list vec i end procs))
        ((eq? (car tok) ':word)
         (let* ((name (cadr tok)))
           (cond
             ;; THING as an expression: THING :X / THING "X"
             ((equal? name "THING")
              (let* ((name-parsed (logo-parse-expr vec (+ i 1) end procs)))
                (if (error? name-parsed)
                  name-parsed
                  (cons (list ':thing (car name-parsed)) (cdr name-parsed)))))
             (#t
              ;; A word in argument position is either a value-primitive call,
              ;; a procedure call, or a bare word (THING semantics).
              (let* ((arity (logo-primitive-arity name)))
                (if (and arity (hash-ref *logo-value-primitives* name))
                  (let loop ((j (+ i 1))
                             (args nil)
                             (n arity))
                    (if (= n 0)
                      (cons (list ':call name (reverse args)) j)
                      (let* ((arg-parsed (logo-parse-expr vec j end procs)))
                        (if (error? arg-parsed)
                          arg-parsed
                          (loop (cdr arg-parsed)
                           (cons (car arg-parsed) args)
                           (- n 1))))))
                  (let* ((parity (hash-ref procs name)))
                    (if parity
                      (let loop ((j (+ i 1))
                                 (args nil)
                                 (n parity))
                        (if (= n 0)
                          (cons (list ':call name (reverse args)) j)
                          (let* ((arg-parsed (logo-parse-expr vec j end procs)))
                            (if (error? arg-parsed)
                              arg-parsed
                              (loop (cdr arg-parsed)
                               (cons (car arg-parsed) args)
                               (- n 1))))))
                      (cons (list ':word name) (+ i 1))))))))))
        (#t
         (error (format nil "unexpected token in expression: ~a" tok)))))))

(defun logo-parse-list (vec i end procs)
  "Parse [ expr ... ] data list at VEC[I]. Returns ((:list ...) . next)."
  (let loop ((k (+ i 1))
             (elements nil))
    (if (>= k end)
      (error "unterminated [")
      (let* ((tok (vector-ref vec k)))
        (if (equal? tok '(:rbracket))
          (cons (list ':list (reverse elements)) (+ k 1))
          (let* ((parsed (logo-parse-expr vec k end procs)))
            (if (error? parsed)
              parsed
              (loop (cdr parsed) (cons (car parsed) elements)))))))))
