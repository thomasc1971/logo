;; tui.lisp - Interactive Logo TUI (Tapestry Elm application)
;;
;; Layout (inspired by the RC759 Piccoline's split screen: picture above,
;; work area below):
;;
;;   +------------------------------------------------------------+
;;   | Logo - turtle graphics                                     |
;;   +------------------------------------------------------------+
;;   |  <braille canvas>                                          |
;;   +------------------------------------------------------------+
;;   |  <transcript: PRINT output and errors>                     |
;;   +------------------------------------------------------------+
;;   | ? <input line>                                             |
;;   +------------------------------------------------------------+
;;   | FD 100  RT 90  REPEAT 4 [...]  q quit  up/down history     |
;;   +------------------------------------------------------------+
;;
;; The model is an alist; the interpreter state lives inside it so TO
;; definitions and MAKE variables survive across REPL lines.
;;
;; Requires an installed Tapestry. Headless use (tests, CLI) never calls
;; app-run: see logo-repl-eval and logo.lisp's logo-run.
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-tui)

;; Tapestry is required lazily in logo-tui-main, not at load time, so that
;; headless users (tests, CLI) can load `logo` without Tapestry installed.

;; ---------------------------------------------------------------------------
;; Model
;; ---------------------------------------------------------------------------
(defun logo-model-make ()
  "Create the initial TUI model.
   CAPS comes from Ditty's env-only fallback (no I/O, no query); the app
   loop replaces it with the `capabilities` message when the probe answers."
  (let* ((caps (terminal:terminal-capabilities-from-replies nil)))
    (list (cons 'state (logo-interp-make 200 200))
     (cons 'input "")
     (cons 'history nil)
     (cons 'hist-index nil)
     (cons 'transcript (list "Type Logo commands, e.g. FD 100 RT 90 FD 100"))
     (cons 'caps caps)
     (cons 'backend (logo-graphics-backend-from caps))
     (cons 'error nil))))

(defun logo-model-state (m) (cdr (assoc 'state m)))

(defun logo-model-input (m) (cdr (assoc 'input m)))

(defun logo-model-transcript (m) (cdr (assoc 'transcript m)))

(defun logo-model-error (m) (cdr (assoc 'error m)))

(defun logo-model-with (m key value)
  "Return a copy of model M with KEY set to VALUE."
  (let* ((bindings nil))
    (let loop ((rest m))
      (if (null? rest)
        nil
        (let* ((b (car rest)))
          (when (not (eq? (car b) key)) (set! bindings (cons b bindings)))
          (loop (cdr rest)))))
    (cons (cons key value) (reverse bindings))))

(defun logo-model-append-transcript (m lines)
  "Append LINES (list of strings) to the transcript, keeping the last 32."
  (let* ((all (append (logo-model-transcript m) lines)))
    (logo-model-with m 'transcript
     (if (> (length all) 32)
       (let drop ((rest all))
         (if (> (length rest) 32) (drop (cdr rest)) rest))
       all))))

;; ---------------------------------------------------------------------------
;; REPL evaluation (shared by the TUI and headless callers)
;; ---------------------------------------------------------------------------
(defun logo-repl-eval (state source)
  "Evaluate one Logo SOURCE string in interpreter STATE.
   Returns (NEW-STATE . RESULT-LINES): RESULT-LINES is a list of strings
   (PRINT output plus a trailing error line if evaluation failed).

   Ditty's condition-case substitutes the handler result at the error
   site and resumes, so the handlers below return the error object
   itself; the surrounding code then error?-checks it like any other
   value. Never let a handler result flow into destructuring code."
  (let* ((parsed (condition-case err (logo-parse source) (error err))))
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

;; ---------------------------------------------------------------------------
;; Update
;; ---------------------------------------------------------------------------
(defun logo-tui-update (model msg)
  "Elm update function for the Logo TUI."
  (cond
    ((tapestry:key-event? msg)
     (let* ((key (tapestry:key-name msg)))
       (cond
         ((equal? key "return")
          (logo-tui-submit model))
         ((equal? key "backspace")
          (let* ((input (logo-model-input model)))
            (logo-model-with model 'input
             (if (> (length input) 0)
               (substring input 0 (- (length input) 1))
               input))))
         ((equal? key "up")
          (logo-tui-history model 1))
         ((equal? key "down")
          (logo-tui-history model -1))
         ((and (equal? key "q") (equal? (logo-model-input model) ""))
          (tapestry:app-quit)
          model)
         ((and (equal? key "escape") (equal? (logo-model-input model) ""))
          (tapestry:app-quit)
          model)
         ;; Ditty names a key by its decoded UTF-8 code point, so a
         ;; non-ASCII letter is a one-character name and types as text.
         ((and (= (length key) 1) (>= (char-code (string-ref key 0)) 32))
          (logo-model-with model 'input (concat (logo-model-input model) key)))
         (#t model))))
    ((tapestry:focus-event? msg)
     (when (equal? (cdr (assoc 'focus msg)) 'out) (tapestry:app-quit))
     model)
    ((and (pair? msg) (equal? (cdr (assoc 'type msg)) 'capabilities))
     ;; Tapestry's loop probes the terminal once at startup and delivers the
     ;; answer here (the view re-renders right after). The probe may never
     ;; answer on a terminal that ignores DA1, so the env-only fallback from
     ;; logo-model-make stays in charge until this arrives.
     (let* ((caps (cdr (assoc 'caps msg)))
            (m (logo-model-with model 'caps caps)))
       (logo-model-with m 'backend (logo-graphics-backend-from caps))))
    (#t model)))

(defun logo-tui-submit (model)
  "Evaluate the current input line and clear it."
  (let* ((input (logo-model-input model)))
    (if (equal? (string-trim input) "")
      model
      (let* ((result (logo-repl-eval (logo-model-state model) input))
             (new-state (car result))
             (lines (cdr result)))
        (let* ((m (logo-model-with model 'state new-state)))
          (let* ((m2 (logo-model-with m 'input "")))
            (let* ((m3
                    (logo-model-with m2 'history
                     (cons input (cdr (assoc 'history m))))))
              (let* ((m4 (logo-model-with m3 'hist-index nil)))
                (logo-model-append-transcript m4 lines)))))))))

(defun logo-history-nth (history index)
  "Return the INDEX-th (0-based, newest first) entry of HISTORY."
  (let loop ((rest history)
             (n index))
    (if (or (null? rest) (= n 0))
      (car rest)
      (loop (cdr rest) (- n 1)))))

(defun logo-tui-history (model direction)
  "Move through command history. DIRECTION 1 = older, -1 = newer.
   'hist-index nil means not browsing; browsing past the newest entry
   clears the input line and returns to the not-browsing state."
  (let* ((history (cdr (assoc 'history model)))
         (index (cdr (assoc 'hist-index model))))
    (if (null? history)
      model
      (if (= direction 1)
        (let* ((at
                (if (null? index)
                  0
                  (min (+ index 1) (- (length history) 1))))
               (m (logo-model-with model 'hist-index at)))
          (logo-model-with m 'input (logo-history-nth history at)))
        (if (null? index)
          model
          (if (= index 0)
            (let* ((m (logo-model-with model 'hist-index nil)))
              (logo-model-with m 'input ""))
            (let* ((at (- index 1))
                   (m (logo-model-with model 'hist-index at)))
              (logo-model-with m 'input (logo-history-nth history at)))))))))

;; ---------------------------------------------------------------------------
;; View
;; ---------------------------------------------------------------------------
(defun logo-tui-view (model)
  "Elm view function: returns a list of lines for the terminal."
  (let* ((size (tapestry:app-screen-size))
         (width (if size (cdr size) 80))
         (height (if size (car size) 24))
         (canvas-cols (- width 4))
         (canvas-rows (max 3 (- height 12)))
         (turtle (logo-interp-turtle (logo-model-state model)))
         (canvas-lines
          (canvas->braille-lines (turtle-canvas turtle)
           canvas-cols canvas-rows))
         (transcript (logo-model-transcript model))
         (shown
          (if (> (length transcript) 4)
            (let drop ((rest transcript))
              (if (> (length rest) 4) (drop (cdr rest)) rest))
            transcript))
         (backend (cdr (assoc 'backend model))))
    (append
     (list (tapestry:box-line "Logo - turtle graphics" width "single" "center")
      (tapestry:box-top width "single"))
     (map
      (lambda (line) (concat "│ " (tapestry:pad-right line (- width 4)) " │"))
      canvas-lines)
     (list (tapestry:box-bottom width "single")
      (tapestry:center
       (format nil "backend: ~a   turtle: (~a, ~a) heading ~a"
        backend
        (floor (turtle-x turtle))
        (floor (turtle-y turtle))
        (floor (turtle-heading turtle)))
       width))
     (map
      (lambda (line)
        (tapestry:pad-right (tapestry:truncate-to-width line width) width)) shown)
     (list (tapestry:hr width)
      (concat "? " (logo-model-input model))
      ""))))

;; ---------------------------------------------------------------------------
;; Entry point
;; ---------------------------------------------------------------------------
(defun logo-tui-main ()
  "Run the interactive Logo TUI (requires a TTY and Tapestry).
   Tapestry symbols are used qualified (tapestry:...) throughout this
   module: use-package inside a function body does not reliably extend
   the defining package's used-packages at call time."
  (require 'tapestry)
  (tapestry:app-run (logo-model-make) logo-tui-update logo-tui-view nil
   (list (cons :mouse #f) (cons :focus #f) (cons :paste #t))))
