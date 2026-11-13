;; repl.lisp - Headless REPL evaluation
;;
;; Shared by the TUI and headless callers: parse one submitted line in the
;; selected dialect, run it, and return only the transcript lines it added.
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-repl)

;; ---------------------------------------------------------------------------
;; REPL evaluation (shared by the TUI and headless callers)
;; ---------------------------------------------------------------------------
(defun logo-repl-eval (state source &optional dialect)
  "Evaluate one Logo SOURCE string in interpreter STATE.
   DIALECT is 'logo (default) or 'mikro. Returns (NEW-STATE . RESULT-LINES):
   RESULT-LINES is a list of strings (PRINT output plus a trailing error
   line if evaluation failed).

   Ditty's condition-case substitutes the handler result at the error
   site and resumes, so the handlers below return the error object
   itself; the surrounding code then error?-checks it like any other
   value. Never let a handler result flow into destructuring code."
  (let* ((parsed
          (condition-case err
            (if (eq? dialect 'mikro)
              (logo-mikro-parse source 'command-line
               (logo-interp-procedure-arities state))
              (logo-parse source))
            (error err))))
    (if (error? parsed)
      (cons state (list (format nil "Error: ~a" (error-message parsed))))
      (let* ((new-state
              (condition-case err (logo-eval-program state parsed) (error err))))
        (if (error? new-state)
          (cons state (list (format nil "Error: ~a" (error-message new-state))))
          (cons new-state
           (logo-new-output-lines state new-state)))))))

(defun logo-new-output-lines (old-state new-state)
  "Return only the transcript lines NEW-STATE added over OLD-STATE.
   Turtle output accumulates in the turtle, so returning the whole
   transcript on every REPL line would re-print all previous PRINTs."
  (let* ((old-lines (turtle-output (logo-interp-turtle old-state)))
         (new-lines (turtle-output (logo-interp-turtle new-state))))
    (let loop ((rest new-lines)
               (n (length old-lines)))
      (if (= n 0)
        rest
        (loop (cdr rest) (- n 1))))))
