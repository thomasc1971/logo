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
;; In Mikro mode the same model drives the modal LÆR/RET procedure editor:
;; the editor replaces the drawing area, and A4 compiles the 21-line page.
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
(defun logo-model-make (&optional dialect)
  "Create the initial TUI model for DIALECT ('logo or 'mikro).
   CAPS comes from Ditty's env-only fallback (no I/O, no query); the app
   loop replaces it with the `capabilities` message when the probe answers."
  (let* ((caps (terminal:terminal-capabilities-from-replies nil))
         (dialect (if (null? dialect) 'logo dialect)))
    (list (cons 'state (logo-interp-make 200 200))
     (cons 'input (logo-command-line-make))
     (cons 'history nil)
     (cons 'hist-index nil)
     (cons 'transcript (list "Type Logo commands, e.g. FD 100 RT 90 FD 100"))
     (cons 'caps caps)
     (cons 'backend (logo-graphics-backend-from caps))
     (cons 'error nil)
     (cons 'dialect dialect)
     (cons 'editor nil)
     (cons 'message nil)
     (cons 'prompt nil)
     (cons 'draft nil)
     (cons 'draft-name nil))))

(defun logo-model-state (m) (cdr (assoc 'state m)))

(defun logo-model-command-line (m) (cdr (assoc 'input m)))

(defun logo-model-input (m)
  (logo-command-line-text (logo-model-command-line m)))

(defun logo-model-cursor (m)
  (logo-command-line-cursor (logo-model-command-line m)))

(defun logo-model-transcript (m) (cdr (assoc 'transcript m)))

(defun logo-model-error (m) (cdr (assoc 'error m)))

(defun logo-model-dialect (m) (cdr (assoc 'dialect m)))

(defun logo-model-editor (m) (cdr (assoc 'editor m)))

(defun logo-model-message (m) (cdr (assoc 'message m)))

(defun logo-model-prompt (m) (cdr (assoc 'prompt m)))

(defun logo-model-draft (m) (cdr (assoc 'draft m)))

(defun logo-model-draft-name (m) (cdr (assoc 'draft-name m)))

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

(defun logo-model-with-command-line (m cl)
  "Return M with command line CL (text . cursor)."
  (logo-model-with m 'input cl))

(defun logo-model-with-input (m text)
  "Return M with TEXT on the command line and the cursor at its end."
  (logo-model-with-command-line m (logo-command-line-make text)))

(defun logo-model-append-transcript (m lines)
  "Append LINES (list of strings) to the transcript, keeping the last 32."
  (let* ((all (append (logo-model-transcript m) lines)))
    (logo-model-with m 'transcript
     (if (> (length all) 32)
       (let drop ((rest all))
         (if (> (length rest) 32) (drop (cdr rest)) rest))
       all))))

;; ---------------------------------------------------------------------------
;; Mikro commands
;; ---------------------------------------------------------------------------
(define *logo-tui-command-words*
  ;; System commands (manual §5). F1 skips command lines when it recalls the
  ;; previous sentence line (manual §3); turtle sentences such as SLET are
  ;; not commands and stay recallable.
  (list "FARVEL" "FORTRYDE" "GEM" "GLEM" "HENT" "HJÆLP" "HVILKE" "KATALOG"
   "KOPI" "LAV" "LIST" "LÆR" "PDISK" "PHJÆLP" "PIL" "RET" "STATUS" "TEGNING"
   "UDPORT"))

(defun logo-tui-words (input)
  "Split INPUT on spaces, dropping empty pieces."
  (filter (lambda (word) (not (equal? word "")))
   (string-split (string-trim input) " ")))

(defun logo-tui-open-editor (model editor)
  "Put EDITOR on screen and return to editor mode."
  (let* ((m (logo-model-with model 'editor editor)))
    (let* ((m2 (logo-model-with-input m "")))
      (let* ((m3 (logo-model-with m2 'prompt nil)))
        (let* ((m4 (logo-model-with m3 'message nil)))
          m4)))))

(defun logo-tui-open-learn (model)
  (if (eq? (logo-model-dialect model) 'mikro)
    (logo-tui-open-editor model (logo-editor-learn))
    model))

(defun logo-tui-editor-procedure-name (editor)
  "Best-effort procedure name from EDITOR's header line."
  (let* ((words (logo-tui-words (car (logo-editor-lines editor)))))
    (if
      (and (pair? words) (equal? (logo-upcase (car words)) "BEGYND")
           (pair? (cdr words)))
      (logo-upcase (cadr words))
      nil)))

(defun logo-tui-open-ret (model name)
  "Open procedure NAME for editing, preferring a failed draft."
  (let* ((key (logo-upcase name))
         (state (logo-model-state model))
         (source (logo-interp-procedure-source state key))
         (draft (logo-model-draft model))
         (draft-name (logo-model-draft-name model)))
    (cond
      ((and (not (null? draft)) (equal? draft-name key))
       (logo-tui-open-editor model
        (logo-editor-ret (logo-editor-lines draft) key)))
      ((not (null? source))
       (logo-tui-open-editor model (logo-editor-ret source key)))
      (#t
       (let* ((m
               (logo-model-with model 'message
                (format nil "~a findes ikke" key))))
         (logo-model-with-input m ""))))))

(defun logo-tui-prompt-ret (model)
  (let* ((m (logo-model-with model 'prompt 'ret-name)))
    (let* ((m2 (logo-model-with m 'message "procedurenavn?")))
      (logo-model-with-input m2 ""))))

(defun logo-tui-command (model input)
  "Dispatch a Mikro command line. Returns (HANDLED . MODEL)."
  (let* ((words (logo-tui-words input)))
    (if (null? words)
      (cons #f model)
      (let* ((name (logo-upcase (car words))))
        (cond
          ((equal? name "LÆR") (cons #t (logo-tui-open-learn model)))
          ((equal? name "RET")
           (cons #t
            (if (pair? (cdr words))
              (logo-tui-open-ret model (cadr words))
              (logo-tui-prompt-ret model))))
          ((equal? name "FARVEL")
           (tapestry:app-quit)
           (cons #t model))
          (#t (cons #f model)))))))

(defun logo-tui-submit (model)
  "Evaluate the current input line and clear it."
  (let* ((input (logo-model-input model)))
    (if (equal? (string-trim input) "")
      model
      (cond
        ((eq? (logo-model-prompt model) 'ret-name)
         (let* ((name (string-trim input)))
           (if (equal? name "")
             model
             (let* ((m (logo-model-with-input model "")))
               (let* ((m2 (logo-model-with m 'prompt nil)))
                 (logo-tui-open-ret m2 name))))))
        ((eq? (logo-model-dialect model) 'mikro)
         (let* ((command (logo-tui-command model input)))
           (if (car command)
             (cdr command)
             (logo-tui-eval-input model input))))
        (#t (logo-tui-eval-input model input))))))

(defun logo-tui-eval-input (model input)
  "Evaluate INPUT in the model's dialect and record the result."
  (let* ((result
          (logo-repl-eval (logo-model-state model) input
           (logo-model-dialect model)))
         (new-state (car result))
         (lines (cdr result)))
    (let* ((m (logo-model-with model 'state new-state)))
      (let* ((m2 (logo-model-with-input m "")))
        (let* ((m3
                (logo-model-with m2 'history
                 (cons input (cdr (assoc 'history m))))))
          (let* ((m4 (logo-model-with m3 'hist-index nil)))
            (logo-model-append-transcript m4 lines)))))))

;; ---------------------------------------------------------------------------
;; Editor transitions
;; ---------------------------------------------------------------------------
(defun logo-tui-editor-commit (model)
  "Compile the active editor. On success install the procedure, else block."
  (let* ((editor (logo-model-editor model))
         (state (logo-model-state model))
         (result
          (logo-mikro-compile-lines (logo-editor-lines editor)
           (logo-interp-procedure-arities state))))
    (if (eq? (car result) 'ok)
      (let* ((name (cadr result))
             (params (caddr result))
             (body (cadddr result))
             (source (list-ref result 4))
             (state2
              (logo-interp-define-procedure state name params body source)))
        (let* ((m (logo-model-with model 'state state2)))
          (let* ((m2 (logo-model-with m 'editor nil)))
            (let* ((m3 (logo-model-with m2 'message nil)))
              (let* ((m4 (logo-model-with m3 'draft nil)))
                (logo-model-with m4 'draft-name nil))))))
      (let* ((message (cadr result))
             (state2 (logo-interp-with-blocked state message))
             (draft-name
              (or (logo-editor-name editor)
                  (logo-tui-editor-procedure-name editor)))
             (m (logo-model-with model 'state state2)))
        (let* ((m2 (logo-model-with m 'editor nil)))
          (let* ((m3 (logo-model-with m2 'message message)))
            (let* ((m4 (logo-model-with m3 'draft editor)))
              (logo-model-with m4 'draft-name draft-name))))))))

(defun logo-tui-editor-cancel (model)
  (let* ((blocked (logo-interp-blocked (logo-model-state model)))
         (m (logo-model-with model 'editor nil)))
    (let* ((m2 (logo-model-with-input m "")))
      (logo-model-with m2 'message
       (if (null? blocked) nil blocked)))))

(defun logo-tui-editor-key (model msg)
  "Handle one key event while the procedure editor is active."
  (let* ((key (tapestry:key-name msg))
         (editor (logo-model-editor model))
         (text (logo-tui-key-text msg key)))
    (cond
      ((equal? key "escape") (logo-tui-editor-cancel model))
      ((equal? key "C-s") (logo-tui-editor-commit model))
      ((equal? key "C-k")
       (logo-model-with model 'editor (logo-editor-kill-to-end editor)))
      ((equal? key "C-d")
       (logo-model-with model 'editor (logo-editor-delete-line editor)))
      ((equal? key "C-o")
       (logo-model-with model 'editor (logo-editor-insert-line editor)))
      ((equal? key "left")
       (logo-model-with model 'editor (logo-editor-move-left editor)))
      ((equal? key "right")
       (logo-model-with model 'editor (logo-editor-move-right editor)))
      ((equal? key "up")
       (logo-model-with model 'editor (logo-editor-move-up editor)))
      ((equal? key "down")
       (logo-model-with model 'editor (logo-editor-move-down editor)))
      ((equal? key "home")
       (logo-model-with model 'editor (logo-editor-home editor)))
      ((equal? key "end")
       (logo-model-with model 'editor (logo-editor-end editor)))
      ((equal? key "backspace")
       (logo-model-with model 'editor (logo-editor-backspace editor)))
      ((equal? key "delete")
       (logo-model-with model 'editor (logo-editor-delete editor)))
      ((equal? key "insert")
       (logo-model-with model 'editor (logo-editor-insert-space editor)))
      ((equal? key "return")
       (let* ((result (logo-editor-return editor)))
         (if (eq? (car result) 'commit)
           (logo-tui-editor-commit model)
           (logo-model-with model 'editor (cdr result)))))
      ((not (null? text))
       (logo-model-with model 'editor (logo-editor-insert-text editor text)))
      (#t model))))

(defun logo-tui-key-text (msg key)
  "Return insertable text for MSG, falling back to a one-character KEY.
   The fallback keeps synthetic key events in tests working."
  (let* ((text (tapestry:key-text msg)))
    (if (string? text)
      text
      (if (and (= (length key) 1) (>= (char-code (string-ref key 0)) 32))
        key
        nil))))

;; ---------------------------------------------------------------------------
;; Update
;; ---------------------------------------------------------------------------
(defun logo-tui-type-key (model msg key)
  "Insert the printable text of MSG at the command line cursor."
  (let* ((text (logo-tui-key-text msg key)))
    (if (null? text)
      model
      (logo-model-with-command-line model
       (logo-command-line-insert-text (logo-model-command-line model) text)))))

(defun logo-tui-cancel-line (model)
  "Handle Escape outside the editor: abandon and clear the line."
  (cond
    ((eq? (logo-model-prompt model) 'ret-name)
     (let* ((m (logo-model-with model 'prompt nil)))
       (let* ((m2 (logo-model-with m 'message nil)))
         (logo-model-with-input m2 ""))))
    ((eq? (logo-model-dialect model) 'logo)
     (if (equal? (logo-model-input model) "")
       (progn (tapestry:app-quit) model)
       (logo-model-with-input model "")))
    (#t (logo-model-with-input model ""))))

(defun logo-tui-normal-key (model msg key)
  "Handle one key event outside the procedure editor.
   The editing keys follow the RC759 command line (manual §3): left/right
   move the cursor, up/down go to the start/end of the line in Mikro mode
   (the English dialect keeps them for history), Insert inserts a blank,
   Delete removes the character under the cursor, and C-k (A1) kills the
   rest of the line. F1 recalls the previous sentence line in Mikro mode."
  (let* ((dialect (logo-model-dialect model))
         (cl (logo-model-command-line model)))
    (cond
      ((and (eq? dialect 'mikro) (equal? key "f5"))
       (logo-tui-open-learn model))
      ((and (eq? dialect 'mikro) (equal? key "f6"))
       (logo-tui-prompt-ret model))
      ((and (eq? dialect 'mikro) (equal? key "f1"))
       (logo-tui-recall-sentence-line model))
      ((equal? key "return") (logo-tui-submit model))
      ((equal? key "left")
       (logo-model-with-command-line model (logo-command-line-left cl)))
      ((equal? key "right")
       (logo-model-with-command-line model (logo-command-line-right cl)))
      ((equal? key "home")
       (logo-model-with-command-line model (logo-command-line-start cl)))
      ((equal? key "end")
       (logo-model-with-command-line model (logo-command-line-finish cl)))
      ((and (eq? dialect 'mikro) (equal? key "up"))
       (logo-model-with-command-line model (logo-command-line-start cl)))
      ((and (eq? dialect 'mikro) (equal? key "down"))
       (logo-model-with-command-line model (logo-command-line-finish cl)))
      ((equal? key "up") (logo-tui-history model 1))
      ((equal? key "down") (logo-tui-history model -1))
      ((equal? key "backspace")
       (logo-model-with-command-line model (logo-command-line-backspace cl)))
      ((equal? key "delete")
       (logo-model-with-command-line model (logo-command-line-delete cl)))
      ((equal? key "insert")
       (logo-model-with-command-line model
        (logo-command-line-insert-space cl)))
      ((equal? key "C-k")
       (logo-model-with-command-line model
        (logo-command-line-kill-to-end cl)))
      ((and (eq? dialect 'logo) (equal? key "q")
            (equal? (logo-model-input model) ""))
       (tapestry:app-quit)
       model)
      ((equal? key "escape") (logo-tui-cancel-line model))
      (#t (logo-tui-type-key model msg key)))))

(defun logo-tui-key-dispatch (model msg)
  "Route a key event to the editor or the command line."
  (let* ((key (tapestry:key-name msg)))
    (if (not (null? (logo-model-editor model)))
      (logo-tui-editor-key model msg)
      (logo-tui-normal-key model msg key))))

(defun logo-tui-update (model msg)
  "Elm update function for the Logo TUI."
  (cond
    ((tapestry:key-event? msg) (logo-tui-key-dispatch model msg))
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
          (logo-model-with-input m (logo-history-nth history at)))
        (if (null? index)
          model
          (if (= index 0)
            (let* ((m (logo-model-with model 'hist-index nil)))
              (logo-model-with-input m ""))
            (let* ((at (- index 1))
                   (m (logo-model-with model 'hist-index at)))
              (logo-model-with-input m (logo-history-nth history at)))))))))

(defun logo-tui-sentence-line? (line)
  "True when LINE holds turtle sentences rather than a Mikro command.
   The RC759 F1 key recalls the previous sentence line (manual §3), so
   command lines such as LÆR and RET are skipped."
  (let* ((words (logo-tui-words line)))
    (if (null? words)
      #f
      (not (member (logo-upcase (car words)) *logo-tui-command-words*)))))

(defun logo-tui-recall-sentence-line (model)
  "Recall the previous sentence line (manual §3: F1).
   Repeated presses walk further back through the history."
  (let* ((history (cdr (assoc 'history model)))
         (index (cdr (assoc 'hist-index model)))
         (start (if (null? index) 0 (+ index 1))))
    (let loop ((n start))
      (if (>= n (length history))
        model
        (let* ((line (logo-history-nth history n)))
          (if (logo-tui-sentence-line? line)
            (let* ((m (logo-model-with model 'hist-index n)))
              (logo-model-with-input m line))
            (loop (+ n 1))))))))

;; ---------------------------------------------------------------------------
;; View
;; ---------------------------------------------------------------------------
(defun logo-tui-slice (text left width)
  "Return TEXT from column LEFT, at most WIDTH characters."
  (let* ((len (length text))
         (start (min left len))
         (end (min len (+ start width))))
    (substring text start end)))

(defun logo-tui-cursor-line (text col width left)
  "Render TEXT with an inverse-video block at COL, horizontally from LEFT."
  (let* ((len (length text))
         (start (min left len))
         (end (min len (+ start width)))
         (visible (substring text start end))
         (rel (- col start))
         (vlen (length visible)))
    (if (or (< rel 0) (> rel vlen))
      (tapestry:pad-right (tapestry:truncate-to-width visible width) width)
      (let* ((before (substring visible 0 (min rel vlen)))
             (at (if (< rel vlen) (substring visible rel (+ rel 1)) " "))
             (after
              (if (< (+ rel 1) vlen)
                (substring visible (+ rel 1) vlen)
                "")))
        (tapestry:pad-right
         (concat before (tapestry:reverse-video) at (tapestry:reset) after)
         width)))))

(defun logo-tui-command-line-prompt (model)
  "The RC759 prompt for MODEL's command line (manual §3)."
  (cond
    ((eq? (logo-model-prompt model) 'ret-name) "procedurenavn? ")
    ((eq? (logo-model-dialect model) 'mikro) "LOGO> ")
    (#t "? ")))

(defun logo-tui-command-line-view (model width)
  "Render the command line with its block cursor, scrolled to the cursor."
  (let* ((prompt (logo-tui-command-line-prompt model))
         (text (concat prompt (logo-model-input model)))
         (col (+ (length prompt) (logo-model-cursor model)))
         (left (if (>= col (- width 2)) (- col (- width 2)) 0)))
    (logo-tui-cursor-line text col width left)))

(defun logo-tui-editor-view (model)
  "Full-screen editor view: message, 21-line page, status, command line."
  (let* ((size (tapestry:app-screen-size))
         (width (if size (cdr size) 80))
         (height (if size (car size) 24))
         (editor (logo-model-editor model))
         (row (logo-editor-row editor))
         (col (logo-editor-col editor))
         (body-rows (min *logo-editor-lines* (max 1 (- height 3))))
         (top0 (logo-editor-top editor))
         (top
          (cond
            ((< row top0) row)
            ((>= row (+ top0 body-rows)) (- (+ row 1) body-rows))
            (#t top0)))
         (left (if (>= col (- width 2)) (- col (- width 2)) 0))
         (message
          (if (not (null? (logo-model-message model)))
            (logo-model-message model)
            (if (not (null? (logo-editor-error editor)))
              (logo-editor-error editor)
              "")))
         (page
          (let loop ((i top)
                     (n 0)
                     (out nil))
            (if (or (>= i *logo-editor-lines*) (>= n body-rows))
              (reverse out)
              (let* ((text (logo-editor-line editor i))
                     (line
                      (if (= i row)
                        (logo-tui-cursor-line text col width left)
                        (tapestry:pad-right
                         (tapestry:truncate-to-width
                          (logo-tui-slice text left width) width)
                         width))))
                (loop (+ i 1) (+ n 1) (cons line out))))))
         (status
          (tapestry:pad-right
           (tapestry:truncate-to-width
            "A1=C-k slet rest / A2=C-d slet linie / A3=C-o indsæt linie / A4=C-s færdig"
            width)
           width)))
    (append
     (list
      (tapestry:pad-right (tapestry:truncate-to-width message width) width))
     page (list status)
     (list (logo-tui-command-line-view model width)))))

(defun logo-tui-view (model)
  "Elm view function: returns a list of lines for the terminal."
  (if (not (null? (logo-model-editor model)))
    (logo-tui-editor-view model)
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
           (backend (cdr (assoc 'backend model)))
           (message (logo-model-message model)))
      (let* ((body
              (append
               (list
                (tapestry:box-line "Logo - turtle graphics" width "single"
                 "center")
                (tapestry:box-top width "single"))
               (map
                (lambda (line)
                  (concat "│ " (tapestry:pad-right line (- width 4)) " │"))
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
                  (tapestry:pad-right
                   (tapestry:truncate-to-width line width) width))
                shown)
               (list (tapestry:hr width)
                (logo-tui-command-line-view model width)
                ""))))
        (if (null? message)
          body
          (cons
           (tapestry:pad-right (tapestry:truncate-to-width message width) width)
           body))))))

;; ---------------------------------------------------------------------------
;; Entry point
;; ---------------------------------------------------------------------------
(defun logo-tui-main (&optional dialect)
  "Run the interactive Logo TUI (requires a TTY and Tapestry).
   DIALECT is 'logo (default) or 'mikro.
   Tapestry symbols are used qualified (tapestry:...) throughout this
   module: use-package inside a function body does not reliably extend
   the defining package's used-packages at call time."
  (require 'tapestry)
  (tapestry:app-run (logo-model-make dialect) logo-tui-update logo-tui-view nil
   (list (cons :mouse #f) (cons :focus #f) (cons :paste #t))))
