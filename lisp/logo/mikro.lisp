;; mikro.lisp - Mikro-Logo dialect front end
;;
;; The RC759 dialect is line-oriented and uses infix integer expressions,
;; unlike the English bracket/prefix dialect in parser.lisp. This module
;; tokenizes and parses that surface syntax into the shared AST, so the
;; interpreter, turtle, canvas and backends stay common.
;;
;; Token shapes:
;;   (:num N) (:word NAME) (:string S) (:text S) (:op OP)
;;   (:newline) (:semicolon) (:lparen) (:rparen)
;;
;; AST output is the same as parser.lisp:
;;   (cmd NAME args...) (to name params body) (if cond body)
;;   (ifelse cond then else) (repeat count body) (make name value)
;;   (stop) (hvor x y heading)
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-mikro)

;; ---------------------------------------------------------------------------
;; Danish command words
;; ---------------------------------------------------------------------------
(define *logo-mikro-commands*
  (list (list "FREM" "FD" 1)
   (list "FR" "FD" 1)
   (list "TILBAGE" "BK" 1)
   (list "TB" "BK" 1)
   (list "VENSTRE" "LT" 1)
   (list "VE" "LT" 1)
   (list "HØJRE" "RT" 1)
   (list "HØ" "RT" 1)
   (list "TEGN" "PD" 0)
   (list "SLET" "PU" 0)
   (list "LØFT" "PU" 0)
   (list "START" "MIKRO-START" 0)
   (list "VISKUD" "CS" 0)
   (list "HJEM" "HOME" 0)
   (list "SÆTXY" "MIKRO-SETXY" 2)
   (list "SÆTX" "SETX" 1)
   (list "SÆTY" "SETY" 1)
   (list "DREJTIL" "SETH" 1)
   (list "PILIND" "ST" 0)
   (list "PILUD" "HT" 0)))

(defun logo-mikro-command (name)
  "Return (CANONICAL . ARITY) for Danish command NAME, or nil."
  (let loop ((rest *logo-mikro-commands*))
    (if (null? rest)
      nil
      (if (equal? (car (car rest)) name)
        (cons (cadr (car rest)) (caddr (car rest)))
        (loop (cdr rest))))))

;; ---------------------------------------------------------------------------
;; Tokenizer
;; ---------------------------------------------------------------------------
(defun logo-mikro-tokenize (source)
  "Tokenize Mikro-Logo SOURCE, preserving line boundaries."
  (let* ((len (length source)))
    (let loop ((i 0)
               (tokens nil))
      (if (>= i len)
        (reverse tokens)
        (let* ((c (string-ref source i)))
          (cond
            ((or (char=? c #\space) (char=? c #\tab) (char=? c #\return))
             (loop (+ i 1) tokens))
            ((char=? c #\newline)
             (loop (+ i 1) (cons '(:newline) tokens)))
            ((char=? c #\;)
             (loop (+ i 1) (cons '(:semicolon) tokens)))
            ((char=? c #\()
             (loop (+ i 1) (cons '(:lparen) tokens)))
            ((char=? c #\))
             (loop (+ i 1) (cons '(:rparen) tokens)))
            ((char=? c #\")
             (let scan ((j (+ i 1)))
               (if (or (>= j len) (char=? (string-ref source j) #\"))
                 (let* ((text (substring source (+ i 1) j)))
                   (loop (min (+ j 1) len)
                    (cons (list ':string text) tokens)))
                 (scan (+ j 1)))))
            ((char=? c #\:)
             (if (and (< (+ i 1) len) (char=? (string-ref source (+ i 1)) #\=))
               (loop (+ i 2) (cons (list ':op ":=") tokens))
               (error "Ulovligt tegn : i Mikro-Logo")))
            ((char=? c #\<)
             (cond
               ((and (< (+ i 1) len) (char=? (string-ref source (+ i 1)) #\=))
                (loop (+ i 2) (cons (list ':op "<=") tokens)))
               ((and (< (+ i 1) len) (char=? (string-ref source (+ i 1)) #\>))
                (loop (+ i 2) (cons (list ':op "<>") tokens)))
               (#t (loop (+ i 1) (cons (list ':op "<") tokens)))))
            ((char=? c #\>)
             (if (and (< (+ i 1) len) (char=? (string-ref source (+ i 1)) #\=))
               (loop (+ i 2) (cons (list ':op ">=") tokens))
               (loop (+ i 1) (cons (list ':op ">") tokens))))
            ((or (char=? c #\+) (char=? c #\-) (char=? c #\*) (char=? c #\/)
                 (char=? c #\^) (char=? c #\=))
             (loop (+ i 1) (cons (list ':op (char->string c)) tokens)))
            ((char-numeric? c)
             (let scan ((j i))
               (if (or (>= j len) (not (char-numeric? (string-ref source j))))
                 (let* ((text (substring source i j)))
                   (loop j (cons (list ':num (string->number text)) tokens)))
                 (scan (+ j 1)))))
            ((logo-word-start? c)
             (let scan ((j i))
               (if
                 (or (>= j len) (not (logo-word-char? (string-ref source j))))
                 (let* ((name (logo-upcase (substring source i j))))
                   (if (equal? name "SÆTNING")
                     (let rest ((k j))
                       (if
                         (or (>= k len)
                             (char=? (string-ref source k) #\newline))
                         (let* ((text (string-trim (substring source j k))))
                           (loop k
                            (cons (list ':text text)
                             (cons (list ':word name) tokens))))
                         (rest (+ k 1))))
                     (loop j (cons (list ':word name) tokens))))
                 (scan (+ j 1)))))
            (#t
             (error (format nil "Ulovligt tegn ~a i Mikro-Logo" c)))))))))

;; ---------------------------------------------------------------------------
;; Token helpers
;; ---------------------------------------------------------------------------
(defun logo-mikro-word-token? (tok)
  (eq? (car tok) ':word))

(defun logo-mikro-word-of (tok)
  (if (logo-mikro-word-token? tok) (cadr tok) nil))

(defun logo-mikro-op? (tok op)
  (and (eq? (car tok) ':op) (equal? (cadr tok) op)))

(defun logo-mikro-stop-word? (tok words)
  (and (logo-mikro-word-token? tok) (member (cadr tok) words)))

(defun logo-mikro-skip-blank (vec i end mode)
  "Skip newlines and, on command lines, semicolons. Hands back the next index."
  (let loop ((i i))
    (if (>= i end)
      i
      (let* ((tok (vector-ref vec i)))
        (cond
          ((eq? (car tok) ':newline) (loop (+ i 1)))
          ((eq? (car tok) ':semicolon)
           (if (eq? mode 'command-line)
             (loop (+ i 1))
             (error "Kun een sætning pr. linie")))
          (#t i))))))

(defun logo-mikro-expect-line-end (vec i end mode)
  "Require a line terminator at I and return the next index."
  (if (>= i end)
    i
    (let* ((tok (vector-ref vec i)))
      (cond
        ((eq? (car tok) ':newline) (+ i 1))
        ((eq? (car tok) ':semicolon)
         (if (eq? mode 'command-line)
           (+ i 1)
           (error "Kun een sætning pr. linie")))
        (#t
         (error
          (format nil "Mere end eet udtryk: ~a"
           (if (eq? (car tok) ':word) (cadr tok) tok))))))))

(defun logo-mikro-token-text (tok)
  (cond
    ((eq? (car tok) ':word) (cadr tok))
    ((eq? (car tok) ':num) (format nil "~a" (cadr tok)))
    ((eq? (car tok) ':op) (cadr tok))
    (#t (format nil "~a" tok))))

;; ---------------------------------------------------------------------------
;; Pass 1: collect BEGYND procedure arities
;; ---------------------------------------------------------------------------
(defun logo-mikro-merge-procedures (table known)
  "Add the NAME -> arity entries of KNOWN to TABLE and return TABLE."
  (if (null? known)
    table
    (let loop ((entries (hash-entries known)))
      (if (null? entries)
        table
        (let* ((entry (car entries)))
          (hash-set! table (car entry) (cdr entry))
          (loop (cdr entries)))))))

(defun logo-mikro-scan-procedures (tokens)
  "Return a hash NAME -> arity from BEGYND headers in TOKENS."
  (let* ((table (make-hash-table)))
    (let loop ((rest tokens))
      (if (null? rest)
        table
        (let* ((tok (car rest)))
          (if
            (and (logo-mikro-word-token? tok) (equal? (cadr tok) "BEGYND")
                 (not (null? (cdr rest))) (logo-mikro-word-token? (cadr rest)))
            (let* ((name (cadr (cadr rest)))
                   (params
                    (let collect ((s (cddr rest))
                                  (n 0))
                      (if (or (null? s) (not (logo-mikro-word-token? (car s))))
                        n
                        (collect (cdr s) (+ n 1))))))
              (hash-set! table name params)
              (loop (cdr rest)))
            (loop (cdr rest))))))))

;; ---------------------------------------------------------------------------
;; Expressions
;; ---------------------------------------------------------------------------
(defun logo-mikro-parse-primary (vec i end)
  "Parse a primary expression at VEC[I]. Returns (EXPR . NEXT-INDEX)."
  (if (>= i end)
    (error "Navn eller tal mangler")
    (let* ((tok (vector-ref vec i)))
      (cond
        ((or (eq? (car tok) ':newline) (eq? (car tok) ':semicolon)
             (eq? (car tok) ':rparen))
         (error "Navn eller tal mangler"))
        ((eq? (car tok) ':num) (cons (cadr tok) (+ i 1)))
        ((eq? (car tok) ':string)
         (cons (list ':string (cadr tok)) (+ i 1)))
        ((eq? (car tok) ':word)
         (let* ((name (cadr tok)))
           (if
             (and (< (+ i 1) end) (eq? (car (vector-ref vec (+ i 1))) ':lparen))
             (let* ((arg (logo-mikro-parse-expr vec (+ i 2) end)))
               (if (error? arg)
                 arg
                 (if
                   (and (< (cdr arg) end)
                        (eq? (car (vector-ref vec (cdr arg))) ':rparen))
                   (if (equal? name "TLF")
                     (cons (list ':call "RANDOM" (list (car arg)))
                      (+ (cdr arg) 1))
                     (error (format nil "Ukendt funktion: ~a" name)))
                   (error "Højre-parentes mangler"))))
             (cons (list ':mikro-var name) (+ i 1)))))
        ((eq? (car tok) ':lparen)
         (let* ((inner (logo-mikro-parse-expr vec (+ i 1) end)))
           (if (error? inner)
             inner
             (if
               (and (< (cdr inner) end)
                    (eq? (car (vector-ref vec (cdr inner))) ':rparen))
               (cons (car inner) (+ (cdr inner) 1))
               (error "Højre-parentes mangler")))))
        ((logo-mikro-op? tok "+")
         (logo-mikro-parse-primary vec (+ i 1) end))
        ((logo-mikro-op? tok "-")
         (let* ((inner (logo-mikro-parse-primary vec (+ i 1) end)))
           (if (error? inner)
             inner
             (cons (list ':call "MIKRO-NEG" (list (car inner))) (cdr inner)))))
        (#t
         (error
          (format nil "Navn eller tal forventet, ikke ~a"
           (logo-mikro-token-text tok))))))))

(defun logo-mikro-parse-power (vec i end)
  "Parse right-associative ^ at VEC[I]. Returns (EXPR . NEXT-INDEX)."
  (let* ((left (logo-mikro-parse-primary vec i end)))
    (if (error? left)
      left
      (if
        (and (< (cdr left) end)
             (logo-mikro-op? (vector-ref vec (cdr left)) "^"))
        (let* ((right (logo-mikro-parse-power vec (+ (cdr left) 1) end)))
          (if (error? right)
            right
            (cons
             (list ':call "MIKRO-POW" (list (car left) (car right)))
             (cdr right))))
        left))))

(defun logo-mikro-parse-mul (vec i end)
  "Parse * and / at VEC[I]. Returns (EXPR . NEXT-INDEX)."
  (let loop ((left (logo-mikro-parse-power vec i end)))
    (if (error? left)
      left
      (if
        (or (>= (cdr left) end)
            (not
             (or (logo-mikro-op? (vector-ref vec (cdr left)) "*")
                 (logo-mikro-op? (vector-ref vec (cdr left)) "/"))))
        left
        (let* ((op (cadr (vector-ref vec (cdr left))))
               (right (logo-mikro-parse-power vec (+ (cdr left) 1) end)))
          (if (error? right)
            right
            (loop
             (cons
              (if (equal? op "*")
                (list ':call "PRODUCT"
                 (list (list ':list (list (car left) (car right)))))
                (list ':call "QUOTIENT" (list (car left) (car right))))
              (cdr right)))))))))

(defun logo-mikro-parse-add (vec i end)
  "Parse + and - at VEC[I]. Returns (EXPR . NEXT-INDEX)."
  (let loop ((left (logo-mikro-parse-mul vec i end)))
    (if (error? left)
      left
      (if
        (or (>= (cdr left) end)
            (not
             (or (logo-mikro-op? (vector-ref vec (cdr left)) "+")
                 (logo-mikro-op? (vector-ref vec (cdr left)) "-"))))
        left
        (let* ((op (cadr (vector-ref vec (cdr left))))
               (right (logo-mikro-parse-mul vec (+ (cdr left) 1) end)))
          (if (error? right)
            right
            (loop
             (cons
              (if (equal? op "+")
                (list ':call "SUM"
                 (list (list ':list (list (car left) (car right)))))
                (list ':call "DIFFERENCE" (list (car left) (car right))))
              (cdr right)))))))))

(defun logo-mikro-relation-primitive (op)
  (cond
    ((equal? op "=") "MIKRO-EQ")
    ((equal? op "<>") "MIKRO-NE")
    ((equal? op "<") "MIKRO-LT")
    ((equal? op ">") "MIKRO-GT")
    ((equal? op "<=") "MIKRO-LE")
    ((equal? op ">=") "MIKRO-GE")
    (#t nil)))

(defun logo-mikro-parse-relational (vec i end)
  "Parse one relational operator at VEC[I]. Returns (EXPR . NEXT-INDEX)."
  (let* ((left (logo-mikro-parse-add vec i end)))
    (if (error? left)
      left
      (if (>= (cdr left) end)
        left
        (let* ((tok (vector-ref vec (cdr left)))
               (prim
                (if (eq? (car tok) ':op)
                  (logo-mikro-relation-primitive (cadr tok))
                  nil)))
          (if (null? prim)
            left
            (let* ((right (logo-mikro-parse-add vec (+ (cdr left) 1) end)))
              (if (error? right)
                right
                (if
                  (and (< (cdr right) end)
                       (eq? (car (vector-ref vec (cdr right))) ':op)
                       (logo-mikro-relation-primitive
                        (cadr (vector-ref vec (cdr right)))))
                  (error "Fejl i udtryk")
                  (cons
                   (list ':call prim (list (car left) (car right)))
                   (cdr right)))))))))))

(defun logo-mikro-parse-expr (vec i end)
  "Parse one Mikro expression. Returns (EXPR . NEXT-INDEX)."
  (logo-mikro-parse-relational vec i end))

;; ---------------------------------------------------------------------------
;; Statements
;; ---------------------------------------------------------------------------
(defun logo-mikro-parse-until (vec i end procs stops mode)
  "Parse statements until a word in STOPS. Returns (BODY . STOP-INDEX)."
  (let loop ((i i)
             (body nil))
    (let* ((i (logo-mikro-skip-blank vec i end mode)))
      (if (>= i end)
        (error "For mange linier")
        (let* ((tok (vector-ref vec i)))
          (if (logo-mikro-stop-word? tok stops)
            (cons (reverse body) i)
            (let* ((parsed (logo-mikro-parse-instruction vec i end procs mode)))
              (if (error? parsed)
                parsed
                (loop (cdr parsed) (cons (car parsed) body))))))))))

(defun logo-mikro-parse-if (vec i end procs mode)
  "Parse HVIS ... ELLERS ... SLUTHVIS at VEC[I] in MODE."
  (let* ((cond-parsed (logo-mikro-parse-expr vec (+ i 1) end)))
    (if (error? cond-parsed)
      cond-parsed
      (let* ((body-start
              (logo-mikro-expect-line-end vec (cdr cond-parsed) end mode)))
        (let* ((then-parsed
                (logo-mikro-parse-until vec body-start end procs
                 (list "ELLERS" "SLUTHVIS") mode)))
          (if (error? then-parsed)
            then-parsed
            (let* ((stop (vector-ref vec (cdr then-parsed))))
              (if (equal? (cadr stop) "SLUTHVIS")
                (let* ((next
                        (logo-mikro-expect-line-end vec (+ (cdr then-parsed) 1)
                         end
                         mode)))
                  (cons
                   (list 'if
                    (list ':call "MIKRO-NOT-ZERO" (list (car cond-parsed)))
                    (car then-parsed))
                   next))
                (let* ((else-start
                        (logo-mikro-expect-line-end vec (+ (cdr then-parsed) 1)
                         end
                         mode)))
                  (let* ((else-parsed
                          (logo-mikro-parse-until vec else-start end procs
                           (list "SLUTHVIS") mode)))
                    (if (error? else-parsed)
                      else-parsed
                      (let* ((next
                              (logo-mikro-expect-line-end vec
                               (+ (cdr else-parsed) 1) end mode)))
                        (cons
                         (list 'ifelse
                          (list ':call "MIKRO-NOT-ZERO"
                           (list (car cond-parsed)))
                          (car then-parsed) (car else-parsed))
                         next)))))))))))))

(defun logo-mikro-parse-repeat (vec i end procs mode)
  "Parse GENTAG ... HERTIL at VEC[I] in MODE."
  (let* ((count-parsed (logo-mikro-parse-expr vec (+ i 1) end)))
    (if (error? count-parsed)
      count-parsed
      (let* ((body-start
              (logo-mikro-expect-line-end vec (cdr count-parsed) end mode)))
        (let* ((body-parsed
                (logo-mikro-parse-until vec body-start end procs
                 (list "HERTIL")
                 mode)))
          (if (error? body-parsed)
            body-parsed
            (let* ((next
                    (logo-mikro-expect-line-end vec (+ (cdr body-parsed) 1) end
                     mode)))
              (cons (list 'repeat (car count-parsed) (car body-parsed)) next))))))))

(defun logo-mikro-parse-begynd (vec i end procs)
  "Parse BEGYND NAME params ... SLUT at VEC[I]."
  (let* ((j (+ i 1))
         (words
          (let collect ((k j)
                        (acc nil))
            (if
              (or (>= k end) (not (logo-mikro-word-token? (vector-ref vec k))))
              (reverse acc)
              (collect (+ k 1) (cons (cadr (vector-ref vec k)) acc))))))
    (if (null? words)
      (error "Fejl i begynd")
      (let* ((name (car words))
             (params (cdr words))
             (body-start
              (logo-mikro-expect-line-end vec (+ j (length words)) end 'body)))
        (if (> (length params) 6)
          (error "Højst 6 parametre")
          (let* ((body-parsed
                  (logo-mikro-parse-until vec body-start end procs
                   (list "SLUT")
                   'body)))
            (if (error? body-parsed)
              body-parsed
              (let* ((next
                      (logo-mikro-expect-line-end vec (+ (cdr body-parsed) 1)
                       end
                       'procedure)))
                (cons (list 'to name params (car body-parsed)) next)))))))))

(defun logo-mikro-parse-simple (vec i end procs mode)
  "Parse an assignment or command statement at VEC[I]."
  (let* ((name (cadr (vector-ref vec i))))
    (if
      (and (< (+ i 1) end) (eq? (car (vector-ref vec (+ i 1))) ':op)
           (or (equal? (cadr (vector-ref vec (+ i 1))) ":=")
               (equal? (cadr (vector-ref vec (+ i 1))) "=")))
      (let* ((value (logo-mikro-parse-expr vec (+ i 2) end)))
        (if (error? value)
          value
          (let* ((next
                  (logo-mikro-expect-line-end vec (cdr value) end mode)))
            (cons (list 'make (list ':word name) (car value)) next))))
      (let* ((proc-arity (hash-ref procs name))
             (alias (if (null? proc-arity) (logo-mikro-command name) nil)))
        (cond
          ((not (null? proc-arity))
           (logo-mikro-parse-call vec i end name proc-arity mode))
          ((not (null? alias))
           (logo-mikro-parse-call vec i end (car alias) (cdr alias) mode))
          (#t (error (format nil "Hvad betyder ~a?" name))))))))

(defun logo-mikro-parse-call (vec i end name arity mode)
  "Parse a command call to NAME with ARITY arguments at VEC[I]."
  (let loop ((k (+ i 1))
             (n arity)
             (args nil))
    (if (= n 0)
      (let* ((next (logo-mikro-expect-line-end vec k end mode)))
        (cons (cons 'cmd (cons name (reverse args))) next))
      (if (>= k end)
        (error "Navn eller tal mangler")
        (let* ((parsed (logo-mikro-parse-expr vec k end)))
          (if (error? parsed)
            parsed
            (loop (cdr parsed) (- n 1) (cons (car parsed) args))))))))

(defun logo-mikro-parse-instruction (vec i end procs mode)
  "Parse one Mikro statement at VEC[I]. Returns (INSTRUCTION . NEXT-INDEX)."
  (let* ((tok (vector-ref vec i)))
    (if (not (logo-mikro-word-token? tok))
      (error
       (format nil "Navn eller tal forventet, ikke ~a"
        (logo-mikro-token-text tok)))
      (let* ((name (cadr tok)))
        (cond
          ((equal? name "BEGYND")
           (if (eq? mode 'procedure)
             (logo-mikro-parse-begynd vec i end procs)
             (error "sætning/begynd/slut er ikke tilladt")))
          ((equal? name "HVIS")
           (logo-mikro-parse-if vec i end procs mode))
          ((equal? name "GENTAG")
           (logo-mikro-parse-repeat vec i end procs mode))
          ((equal? name "STOP")
           (let* ((next (logo-mikro-expect-line-end vec (+ i 1) end mode)))
             (cons '(stop) next)))
          ((equal? name "SKRIV")
           (let* ((parsed (logo-mikro-parse-expr vec (+ i 1) end)))
             (if (error? parsed)
               parsed
               (let* ((next
                       (logo-mikro-expect-line-end vec (cdr parsed) end mode)))
                 (cons (list 'cmd "PRINT" (car parsed)) next)))))
          ((equal? name "SÆTNING")
           (if
             (and (< (+ i 1) end) (eq? (car (vector-ref vec (+ i 1))) ':text))
             (let* ((text (cadr (vector-ref vec (+ i 1))))
                    (next
                     (logo-mikro-expect-line-end vec (+ i 2) end mode)))
               (cons (list 'cmd "PRINT" (list ':string text)) next))
             (error "Navn eller tal mangler")))
          ((equal? name "HVOR")
           (if (>= (+ i 3) end)
             (error "Navn eller tal mangler")
             (logo-mikro-parse-hvor vec i end mode)))
          (#t (logo-mikro-parse-simple vec i end procs mode)))))))

(defun logo-mikro-parse-hvor (vec i end mode)
  "Parse HVOR X Y H at VEC[I]."
  (let* ((a (vector-ref vec (+ i 1)))
         (b (vector-ref vec (+ i 2)))
         (c (vector-ref vec (+ i 3))))
    (if
      (and (logo-mikro-word-token? a) (logo-mikro-word-token? b)
           (logo-mikro-word-token? c))
      (let* ((next
              (logo-mikro-expect-line-end vec (+ i 4) end mode)))
        (cons (list 'hvor (cadr a) (cadr b) (cadr c)) next))
      (error "X er ikke et navn"))))

;; ---------------------------------------------------------------------------
;; Entry point
;; ---------------------------------------------------------------------------
(defun logo-mikro-parse-program (vec i end procs mode)
  "Parse a Mikro program. Returns (INSTRUCTIONS . NEXT-INDEX)."
  (let loop ((i i)
             (instructions nil))
    (let* ((i (logo-mikro-skip-blank vec i end mode)))
      (if (>= i end)
        (cons (reverse instructions) i)
        (let* ((parsed (logo-mikro-parse-instruction vec i end procs mode)))
          (if (error? parsed)
            parsed
            (loop (cdr parsed) (cons (car parsed) instructions))))))))

(defun logo-mikro-parse (source &optional mode known-procs)
  "Parse Mikro-Logo SOURCE. MODE is 'command-line (default) or 'procedure.
   KNOWN-PROCS is an optional NAME -> arity hash from the interpreter, so a
   line can call procedures defined by earlier submissions.
   Returns a list of instructions, or an error object."
  (let* ((result
          (condition-case err
            (let* ((tokens (logo-mikro-tokenize source))
                   (procs (logo-mikro-scan-procedures tokens))
                   (procs (logo-mikro-merge-procedures procs known-procs))
                   (vec (list->vector tokens))
                   (parsed
                    (logo-mikro-parse-program vec 0 (length vec) procs
                     (if (null? mode) 'command-line mode))))
              (if (error? parsed) parsed (car parsed)))
            (error err))))
    result))

;; ---------------------------------------------------------------------------
;; Procedure compiler for the editor
;; ---------------------------------------------------------------------------
(defun logo-mikro-blank-line? (line)
  (equal? (string-trim line) ""))

(defun logo-mikro-trim-trailing-blanks (lines)
  "Return LINES without trailing blank lines."
  (let loop ((rest (reverse lines))
             (kept nil))
    (if (null? rest)
      kept
      (if (and (null? kept) (logo-mikro-blank-line? (car rest)))
        (loop (cdr rest) kept)
        (loop (cdr rest) (cons (car rest) kept))))))

(defun logo-mikro-words (line)
  "Split LINE into whitespace-separated words, dropping empty pieces."
  (filter (lambda (word) (not (equal? word "")))
   (string-split (string-trim line) " ")))

(defun logo-mikro-name? (name)
  "True if NAME is a legal Mikro procedure or parameter name."
  (and (not (null? name)) (<= (length name) 16)
       (logo-word-start? (string-ref name 0))
       (let loop ((i 1))
         (if (>= i (length name))
           #t
           (let* ((c (string-ref name i)))
             (if (or (logo-letter? c) (char-numeric? c))
               (loop (+ i 1))
               #f))))))

(defun logo-mikro-first-word (line)
  (let* ((words (logo-mikro-words line)))
    (if (null? words) "" (logo-upcase (car words)))))

(defun logo-mikro-indent-body (body)
  "Return BODY with three-space indentation per nesting level.
   The procedure body starts one level in; SLUT itself is appended by the
   compiler at column zero. Returns (INDENTED-LINES . LEVEL) or an error."
  (let loop ((rest body)
             (level 1)
             (out nil))
    (if (null? rest)
      (if (= level 1)
        (cons (reverse out) 1)
        (error "Fejl i løkke"))
      (let* ((raw (car rest))
             (line (string-trim raw))
             (first (logo-mikro-first-word line))
             (dedent?
              (member first (list "SLUT" "HERTIL" "SLUTHVIS" "ELLERS")))
             (level2 (if dedent? (- level 1) level)))
        (if (< level2 0)
          (error "Fejl i løkke")
          (let* ((indented (concat (make-string (* 3 level2) #\space) line))
                 (level3
                  (if (member first (list "HVIS" "GENTAG" "ELLERS"))
                    (+ level2 1)
                    level2)))
            (loop (cdr rest) level3 (cons indented out))))))))

(defun logo-mikro-compile-lines (lines &optional known-procs)
  "Compile editor LINES as one Mikro procedure.
   KNOWN-PROCS is an optional NAME -> arity hash for calls to existing
   procedures. Returns (ok NAME PARAMS BODY CANONICAL-LINES) or
   (error MESSAGE). Compile failures are ordinary tagged values, not
   Ditty errors."
  (let* ((result
          (condition-case err (logo-mikro-compile-lines-1 lines known-procs)
            (error err))))
    (if (error? result)
      (list 'error (error-message result))
      result)))

(defun logo-mikro-header-parts (trimmed)
  "Split TRIMMED into (ok NAME PARAMS BODY) or (error MESSAGE)."
  (if (null? trimmed)
    (list 'error "Fejl i begynd")
    (let* ((header (logo-mikro-words (car trimmed)))
           (body (cdr trimmed)))
      (cond
        ((or (null? header) (not (equal? (logo-upcase (car header)) "BEGYND")))
         (list 'error "Fejl i begynd"))
        ((null? (cdr header)) (list 'error "Fejl i begynd"))
        (#t
         (let* ((name (cadr header))
                (params (cddr header)))
           (cond
             ((not (logo-mikro-name? name))
              (list 'error (format nil "~a skal starte med et bogstav" name)))
             ((> (length params) 6) (list 'error "Højst 6 parametre"))
             ((not (all? logo-mikro-name? params))
              (list 'error "En formel parameter skal starte med et bogstav"))
             (#t (list 'ok name params body)))))))))

(defun logo-mikro-canonical-lines (name params statements)
  "Return (ok CANONICAL-LINES) or (error MESSAGE) for a procedure."
  (let* ((indented (logo-mikro-indent-body statements)))
    (if (error? indented)
      (list 'error (error-message indented))
      (list 'ok
       (append
        (list
         (concat "begynd " name
          (if (null? params) "" (concat " " (join params " ")))))
        (car indented) (list "slut"))))))

(defun logo-mikro-compile-lines-1 (lines known-procs)
  "Worker for LOGO-MIKRO-COMPILE-LINES."
  (let* ((trimmed (logo-mikro-trim-trailing-blanks lines)))
    (let* ((header (logo-mikro-header-parts trimmed)))
      (if (eq? (car header) 'error)
        header
        (let* ((name (cadr header))
               (params (caddr header))
               (body (cadddr header))
               (body-trimmed (logo-mikro-trim-trailing-blanks body))
               (last
                (if (null? body-trimmed)
                  ""
                  (logo-mikro-first-word (car (reverse body-trimmed)))))
               (has-slut (equal? last "SLUT"))
               (statements
                (if has-slut
                  (reverse (cdr (reverse body-trimmed)))
                  body-trimmed)))
          (cond
            ((and (not has-slut) (> (length statements) 19))
             (list 'error "For mange linier"))
            ((and has-slut (> (+ 1 (length statements) 1) 21))
             (list 'error "For mange linier"))
            (#t
             (let* ((canonical
                     (logo-mikro-canonical-lines name params statements)))
               (if (eq? (car canonical) 'error)
                 canonical
                 (let* ((source (join (cadr canonical) "\n"))
                        (parsed
                         (logo-mikro-parse source 'procedure known-procs)))
                   (if (error? parsed)
                     (list 'error (error-message parsed))
                     (if (and (pair? parsed) (eq? (caar parsed) 'to))
                       (list 'ok (cadr (car parsed)) (caddr (car parsed))
                        (cadddr (car parsed)) (cadr canonical))
                       (list 'error "Fejl i begynd")))))))))))))

(defun all? (pred xs)
  "Return #t if PRED is true for every element of XS."
  (if (null? xs)
    #t
    (if (pred (car xs)) (all? pred (cdr xs)) #f)))
