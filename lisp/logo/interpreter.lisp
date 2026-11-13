;; interpreter.lisp - Logo evaluator
;;
;; The interpreter threads a state value through evaluation:
;;
;;   state = ((turtle . T) (globals . HASH) (procs . HASH) (locals . FRAMES)
;;            (sources . HASH) (blocked . NIL-or-STRING))
;;
;;   globals: MAKE variables, hash NAME -> value
;;   procs:   TO definitions, hash NAME -> (PARAMS BODY)
;;   locals:  stack of alists for procedure parameters and LOCAL bindings
;;   sources: procedure name -> canonical source lines (editor/LIST)
;;   blocked: when a Mikro procedure failed to compile, the message that
;;            prevents any user procedure from running until it is fixed
;;
;; Every eval function returns (NEW-STATE . VALUE). OUTPUT and STOP are
;; explicit signal VALUES, not exceptions: (logo-output STATE . VALUE) and
;; (logo-stop . STATE). Ditty's condition-case substitutes the handler
;; result at the error site and resumes execution, which corrupts threaded
;; state if an error object flows through a let* binding -- explicit values
;; with error? checks are deterministic. See logo-repl-eval for how genuine
;; Ditty errors are caught at the boundary.
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-interpreter)

(defun logo-interp-make (width height)
  "Create a fresh interpreter state with a WIDTH x HEIGHT turtle canvas."
  (list (cons 'turtle (turtle-make width height))
   (cons 'globals (make-hash-table))
   (cons 'procs (make-hash-table))
   (cons 'locals nil)
   (cons 'sources (make-hash-table))
   (cons 'blocked nil)))

(defun logo-interp-turtle (s) (cdr (assoc 'turtle s)))

(defun logo-interp-globals (s) (cdr (assoc 'globals s)))

(defun logo-interp-procs (s) (cdr (assoc 'procs s)))

(defun logo-interp-locals (s) (cdr (assoc 'locals s)))

(defun logo-interp-sources (s) (cdr (assoc 'sources s)))

(defun logo-interp-blocked (s) (cdr (assoc 'blocked s)))

(defun logo-interp-with-turtle (s turtle)
  "Return state S with its turtle replaced by TURTLE."
  (list (cons 'turtle turtle)
   (cons 'globals (logo-interp-globals s))
   (cons 'procs (logo-interp-procs s))
   (cons 'locals (logo-interp-locals s))
   (cons 'sources (logo-interp-sources s))
   (cons 'blocked (logo-interp-blocked s))))

(defun logo-interp-with-locals (s locals)
  "Return state S with its locals stack replaced by LOCALS."
  (list (cons 'turtle (logo-interp-turtle s))
   (cons 'globals (logo-interp-globals s))
   (cons 'procs (logo-interp-procs s))
   (cons 'locals locals)
   (cons 'sources (logo-interp-sources s))
   (cons 'blocked (logo-interp-blocked s))))

(defun logo-interp-with-blocked (s message)
  "Return state S with the procedure-execution block set to MESSAGE (or nil)."
  (list (cons 'turtle (logo-interp-turtle s))
   (cons 'globals (logo-interp-globals s))
   (cons 'procs (logo-interp-procs s))
   (cons 'locals (logo-interp-locals s))
   (cons 'sources (logo-interp-sources s))
   (cons 'blocked message)))

(defun logo-interp-define-procedure (s name params body source-lines)
  "Install procedure NAME in state S, remember SOURCE-LINES, clear any block."
  (hash-set! (logo-interp-procs s) name (cons params body))
  (hash-set! (logo-interp-sources s) name source-lines)
  (logo-interp-with-blocked s nil))

(defun logo-interp-procedure-source (s name)
  "Return the stored source lines for NAME, or nil."
  (hash-ref (logo-interp-sources s) name))

(defun logo-interp-procedure-arities (s)
  "Return a hash NAME -> arity for every procedure in state S."
  (let* ((table (make-hash-table)))
    (let loop ((entries (hash-entries (logo-interp-procs s))))
      (if (null? entries)
        table
        (let* ((entry (car entries))
               (name (car entry))
               (proc (cdr entry)))
          (hash-set! table name (length (car proc)))
          (loop (cdr entries)))))))

(defun logo-truthy? (v)
  "Logo truthiness: only #f (and nil) is false."
  (not (or (null? v) (eq? v #f))))

(defun logo-signal? (x)
  "True if X is an OUTPUT/STOP signal value: (logo-output STATE . VALUE)
   or (logo-stop . STATE). Distinct from states (whose car is a binding
   cons) and from (STATE . VALUE) pairs (whose car is a state)."
  (and (pair? x) (or (eq? (car x) 'logo-output) (eq? (car x) 'logo-stop))))

;; ---------------------------------------------------------------------------
;; Variables
;; ---------------------------------------------------------------------------
(defun logo-lookup (s name)
  "Look up variable NAME: locals (innermost first), then globals.
   Returns the value, or nil if unbound (Logo THING of an unbound word)."
  (let loop ((frames (logo-interp-locals s)))
    (if (null? frames)
      (hash-ref (logo-interp-globals s) name)
      (let* ((binding (assoc name (car frames))))
        (if binding
          (cdr binding)
          (loop (cdr frames)))))))

(defun logo-set-var (s name value)
  "MAKE NAME = VALUE in the globals. Returns state S unchanged in shape."
  (hash-set! (logo-interp-globals s) name value)
  s)

(defun logo-var-name (expr)
  "Extract a variable NAME from a name expression (:var, :word, or :string)."
  (cond
    ((and (pair? expr) (eq? (car expr) ':var)) (cadr expr))
    ((and (pair? expr) (eq? (car expr) ':word)) (cadr expr))
    ((and (pair? expr) (eq? (car expr) ':string)) (logo-upcase (cadr expr)))
    ((string? expr) (logo-upcase expr))
    (#t (error (format nil "not a variable name: ~a" expr)))))

;; ---------------------------------------------------------------------------
;; Program evaluation
;; ---------------------------------------------------------------------------
(defun logo-run (source &optional width height dialect mode)
  "Parse and run Logo SOURCE. DIALECT is 'logo (default) or 'mikro.
   MODE is the Mikro parse mode ('procedure by default, or
   'command-line for -e). Returns the final interpreter state, or an
   error object if parsing/evaluation fails. Handlers return the error
   object itself so it can be error?-checked as a value (see
   logo-repl-eval for why condition-case handlers must not produce
   data that flows into destructuring code)."
  (let* ((s (logo-interp-make (or width 200) (or height 200)))
         (parsed
          (condition-case err
            (if (eq? dialect 'mikro)
              (logo-mikro-parse source (if (null? mode) 'procedure mode))
              (logo-parse source))
            (error err))))
    (if (error? parsed)
      parsed
      (condition-case err (logo-eval-program s parsed) (error err)))))

(defun logo-run-file (path &optional width height dialect)
  "Read PATH and run it. Returns the final interpreter state, or an
   error object if PATH cannot be read (missing file, permissions...).
   Like logo-run, the handler returns the error object itself so callers
   can error?-check it instead of crashing on an uncaught Ditty error."
  (let* ((source (condition-case err (read-file-raw path) (error err))))
    (if (error? source)
      source
      (logo-run source width height dialect))))

(defun logo-eval-program (s instructions)
  "Evaluate top-level INSTRUCTIONS. OUTPUT/STOP at top level end the program.
   Returns the final state, or an error object on failure."
  (let* ((result (logo-eval-instructions s instructions)))
    (cond
      ((error? result) result)
      ((logo-signal? result)
       (if (eq? (car result) 'logo-output) (cadr result) (cdr result)))
      (#t result))))

(defun logo-eval-instructions (s instructions)
  "Evaluate a list of instructions, threading state.
   Returns the new state, or an error object (OUTPUT/STOP signals and
   genuine errors both arrive as error values and must be propagated,
   never threaded as if they were states)."
  (let loop ((s s)
             (rest instructions))
    (if (or (null? rest) (error? s) (logo-signal? s))
      s
      (loop (logo-eval-instruction s (car rest)) (cdr rest)))))

(defun logo-eval-instruction (s instr)
  "Evaluate one instruction, returning the new state."
  (cond
    ((eq? (car instr) 'to)
     (hash-set! (logo-interp-procs s) (cadr instr)
      (cons (caddr instr) (cadddr instr)))
     s)
    ((eq? (car instr) 'stop)
     (cons 'logo-stop s))
    ((eq? (car instr) 'output)
     (let* ((result (logo-eval-expr s (cadr instr))))
       (if (error? result)
         result
         (cons 'logo-output result))))
    ((eq? (car instr) 'make)
     (let* ((result (logo-eval-expr s (caddr instr))))
       (if (error? result)
         result
         (progn (logo-set-var s (logo-var-name (cadr instr)) (cdr result)) s))))
    ((eq? (car instr) 'thing)
     ;; THING as a statement: evaluate and discard (propagating errors).
     (let* ((result (logo-eval-expr s (cadr instr))))
       (if (error? result) result (car result))))
    ((eq? (car instr) 'local)
     (let* ((names (logo-local-names (cadr instr))))
       (logo-interp-with-locals
        s (cons (map (lambda (n) (cons n nil)) names) (logo-interp-locals s)))))
    ((eq? (car instr) 'hvor)
     ;; Mikro HVOR: assign x, y and heading to three variables.
     (let* ((t (logo-interp-turtle s))
            (names (cdr instr)))
       (logo-set-var
        (logo-set-var (logo-set-var s (car names) (turtle-x t))
         (cadr names) (turtle-y t))
        (caddr names)
        (turtle-heading t))))
    ((eq? (car instr) 'if)
     (let* ((result (logo-eval-expr s (cadr instr))))
       (if (error? result)
         result
         (if (logo-truthy? (cdr result))
           (logo-eval-instructions (car result) (caddr instr))
           (car result)))))
    ((eq? (car instr) 'ifelse)
     (let* ((result (logo-eval-expr s (cadr instr))))
       (if (error? result)
         result
         (if (logo-truthy? (cdr result))
           (logo-eval-instructions (car result) (caddr instr))
           (logo-eval-instructions (car result) (cadddr instr))))))
    ((eq? (car instr) 'repeat)
     (let loop ((result (logo-eval-expr s (cadr instr)))
                (n nil))
       (if (null? n)
         (if (error? result)
           result
           (loop result (cdr result)))
         (if (<= n 0)
           (car result)
           (loop (cons (logo-eval-instructions (car result) (caddr instr)) nil)
            (- n 1))))))
    ((eq? (car instr) 'run)
     (logo-eval-instructions s (cadr instr)))
    ((eq? (car instr) 'cmd)
     (logo-eval-command s (cadr instr) (cddr instr)))
    (#t (error (format nil "bad instruction: ~a" instr)))))

(defun logo-local-names (expr)
  "Extract variable names from a LOCAL argument (list or single :var)."
  (if (and (pair? expr) (eq? (car expr) ':list))
    (map (lambda (e) (logo-var-name e)) (cadr expr))
    (list (logo-var-name expr))))

(defun logo-eval-command (s name arg-exprs)
  "Evaluate a primitive command NAME with argument expressions ARG-EXPRS.
   Returns the new state, or an error object."
  (let* ((entry (hash-ref *logo-primitives* name)))
    (if entry
      (let loop ((s s)
                 (rest arg-exprs)
                 (args nil))
        (if (error? s)
          s
          (if (null? rest)
            (let* ((new-turtle
                    ((cdr entry) (logo-interp-turtle s) (reverse args))))
              (if (error? new-turtle)
                new-turtle
                (logo-interp-with-turtle s new-turtle)))
            (let* ((result (logo-eval-expr s (car rest))))
              (if (error? result)
                result
                (loop (car result) (cdr rest) (cons (cdr result) args)))))))
      ;; A command that is a procedure call: evaluate args, call, discard value.
      (let* ((result (logo-call-procedure s name arg-exprs)))
        (if (error? result) result (car result))))))

;; ---------------------------------------------------------------------------
;; Expression evaluation: returns (state . value)
;; ---------------------------------------------------------------------------
(defun logo-eval-expr (s expr)
  "Evaluate EXPR in state S. Returns (NEW-STATE . VALUE)."
  (cond
    ((number? expr) (cons s expr))
    ((not (pair? expr)) (cons s expr))
    ((eq? (car expr) ':string) (cons s (cadr expr)))
    ((eq? (car expr) ':var) (cons s (logo-lookup s (cadr expr))))
    ((eq? (car expr) ':mikro-var)
     ;; Mikro variables are numeric and read as 0 before assignment.
     (let* ((value (logo-lookup s (cadr expr))))
       (cons s (if (null? value) 0 value))))
    ((eq? (car expr) ':thing)
     ;; THING with a name expression: THING :X, THING "X, THING X, or a
     ;; computed name (evaluated, then used as the variable name).
     (let* ((name-expr (cadr expr)))
       (if
         (and (pair? name-expr)
              (or (eq? (car name-expr) ':var) (eq? (car name-expr) ':word)
                  (eq? (car name-expr) ':string)))
         (cons s (logo-lookup s (logo-var-name name-expr)))
         (let* ((result (logo-eval-expr s name-expr)))
           (if (error? result)
             result
             (cons (car result)
              (logo-lookup (car result)
               (if (string? (cdr result))
                 (logo-upcase (cdr result))
                 (cdr result)))))))))
    ((eq? (car expr) ':word)
     ;; Bare word: variable value, zero-arg procedure call, else the word
     ;; itself as a string (e.g. PRINT HELLO).
     (let* ((value (logo-lookup s (cadr expr))))
       (cond
         ((not (null? value)) (cons s value))
         ((hash-ref (logo-interp-procs s) (cadr expr))
          (logo-call-procedure s (cadr expr) nil))
         (#t (cons s (cadr expr))))))
    ((eq? (car expr) ':list)
     (let loop ((s s)
                (rest (cadr expr))
                (values nil))
       (if (error? s)
         s
         (if (null? rest)
           (cons s (reverse values))
           (let* ((result (logo-eval-list-element s (car rest))))
             (if (error? result)
               result
               (loop (car result) (cdr rest) (cons (cdr result) values))))))))
    ((eq? (car expr) ':call)
     (logo-eval-call s (cadr expr) (caddr expr)))
    (#t (error (format nil "bad expression: ~a" expr)))))

(defun logo-eval-list-element (s expr)
  "Evaluate one list element. Bare words become their name string (data)."
  (if (and (pair? expr) (eq? (car expr) ':word))
    (cons s (cadr expr))
    (logo-eval-expr s expr)))

(defun logo-eval-call (s name arg-exprs)
  "Evaluate a call to value-primitive or procedure NAME.
   Returns (state . value), or an error object."
  (let* ((entry (hash-ref *logo-value-primitives* name)))
    (if entry
      (let loop ((s s)
                 (rest arg-exprs)
                 (args nil))
        (if (error? s)
          s
          (if (null? rest)
            (let* ((value ((cdr entry) (logo-interp-turtle s) (reverse args))))
              (if (error? value) value (cons s value)))
            (let* ((result (logo-eval-expr s (car rest))))
              (if (error? result)
                result
                (loop (car result) (cdr rest) (cons (cdr result) args)))))))
      (logo-call-procedure s name arg-exprs))))

(defun logo-call-procedure (s name arg-exprs)
  "Call procedure NAME with argument expressions. Returns (state . value)."
  (let* ((blocked (logo-interp-blocked s)))
    (if (not (null? blocked))
      (error blocked)
      (logo-call-procedure-1 s name arg-exprs))))

(defun logo-call-procedure-1 (s name arg-exprs)
  "Call procedure NAME with argument expressions. Returns (state . value)."
  (let* ((proc (hash-ref (logo-interp-procs s) name)))
    (if (null? proc)
      (error (format nil "undefined Logo procedure: ~a" name))
      (let loop ((s s)
                 (rest arg-exprs)
                 (args nil))
        (if (error? s)
          s
          (if (null? rest)
            (logo-invoke s (car proc) (cdr proc) (reverse args))
            (let* ((result (logo-eval-expr s (car rest))))
              (if (error? result)
                result
                (loop (car result) (cdr rest) (cons (cdr result) args))))))))))

(defun logo-invoke (s params body args)
  "Invoke procedure with PARAMS bound to ARGS. Returns (state . value)."
  (if (not (= (length params) (length args)))
    (error
     (format nil "wrong number of arguments: expected ~a, got ~a"
      (length params) (length args)))
    (let* ((frame
            (let loop ((ps params)
                       (as args)
                       (frame nil))
              (if (null? ps)
                (reverse frame)
                (loop (cdr ps) (cdr as) (cons (cons (car ps) (car as)) frame)))))
           (saved-locals (logo-interp-locals s)))
      (let* ((s2 (logo-interp-with-locals s (cons frame saved-locals)))
             (final (logo-eval-instructions s2 body)))
        (cond
          ((error? final) final)
          ((and (logo-signal? final) (eq? (car final) 'logo-output))
           ;; OUTPUT: resume at the caller with the produced value.
           (cons (logo-interp-with-locals (cadr final) saved-locals)
            (cddr final)))
          ((logo-signal? final)
           ;; STOP: resume at the caller, discarding the value.
           (cons (logo-interp-with-locals (cdr final) saved-locals) nil))
          (#t
           (cons (logo-interp-with-locals final saved-locals) nil)))))))
