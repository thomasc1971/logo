;; test-tui.lisp - Headless tests for the Tapestry TUI model/view/update
;;
;; These run without a TTY: they exercise the Elm model functions and the
;; view renderer directly, the same way Tapestry's app loop calls them.
;; Requires an installed Tapestry on the load path (see CONTRIBUTING.md).
(define *test-dir* (or (file-name-directory *load-pathname*) ""))

(set! *load-path* (cons (concat *test-dir* "../lisp/") *load-path*))

(require 'logo)

(use-package 'logo)

(require 'tapestry)

(use-package 'tapestry)

(define passed 0)

(define failed 0)

(defun assert-equal (expected actual description)
  (if (equal? expected actual)
    (progn (format #t "PASS: ~a~%" description) (set! passed (+ passed 1)))
    (progn (format #t "FAIL: ~a~%" description)
      (format #t "  Expected: ~s~%" expected)
      (format #t "  Actual:   ~s~%" actual)
      (set! failed (+ failed 1)))))

(defun assert-true (actual description)
  (assert-equal #t (if actual #t #f) description))

;; Model creation
(let ((m (logo-model-make)))
  (assert-equal "" (logo-model-input m) "model starts with empty input")
  (assert-true (> (length (logo-model-transcript m)) 0)
   "model has welcome transcript"))

;; Capabilities: the model carries Ditty's alist and a backend derived from it
(define *fake-caps*
  (list (cons 'sixel #t) (cons 'kitty-graphics nil) (cons 'iterm2-images nil)
   (cons 'kitty-keyboard 1) (cons 'pixel-size (cons 800 600))
   (cons 'cell-size (cons 10 20)) (cons 'source "query")))

(let* ((m (logo-model-make))
       (caps (cdr (assoc 'caps m)))
       (backend (cdr (assoc 'backend m))))
  (assert-true (pair? caps) "model stores a caps alist")
  (assert-true (member backend '(sixel canvas))
   "model backend is sixel or canvas"))

;; The `capabilities` message from Tapestry's probe updates caps and backend
(let* ((m (logo-model-make))
       (m2
        (logo-tui-update m
         (list (cons 'type 'capabilities) (cons 'caps *fake-caps*)))))
  (assert-equal 'sixel (cdr (assoc 'backend m2))
   "capabilities message selects sixel")
  (assert-equal *fake-caps* (cdr (assoc 'caps m2))
   "capabilities message stores the caps alist"))

;; Tick and reply messages are ignored
(let ((m (logo-model-make)))
  (assert-equal m (logo-tui-update m (list (cons 'type 'tick)))
   "tick leaves the model unchanged")
  (assert-equal m
   (logo-tui-update m (list (cons 'type 'reply) (cons 'replies nil)))
   "reply leaves the model unchanged"))

;; Only a one-character key name is typed text; modified keys are not
(let* ((m (logo-model-make))
       (typed (logo-tui-update m (list (cons 'type 'key) (cons 'key "a"))))
       (modified (logo-tui-update m (list (cons 'type 'key) (cons 'key "M-x")))))
  (assert-equal "a" (logo-model-input typed) "one-character key types text")
  (assert-equal "" (logo-model-input modified) "modified key does not type"))

;; Typing: printable key events append to the input
(let* ((m (logo-model-make))
       (m2 (logo-tui-update m (list (cons 'type 'key) (cons 'key "F"))))
       (m3 (logo-tui-update m2 (list (cons 'type 'key) (cons 'key "D")))))
  (assert-equal "FD" (logo-model-input m3) "typing appends to input"))

;; Backspace deletes the last character
(let* ((m (logo-model-make))
       (m2 (logo-model-with-input m "FDX"))
       (m3
        (logo-tui-update m2 (list (cons 'type 'key) (cons 'key "backspace")))))
  (assert-equal "FD" (logo-model-input m3) "backspace deletes last char"))

;; Ditty decodes multi-byte input in the event parser, so a non-ASCII
;; letter arrives as a one-character key name and types as one character.
(let* ((m (logo-model-with-input (logo-model-make) ""))
       (m2 (logo-tui-update m (list (cons 'type 'key) (cons 'key "å"))))
       (m3 (logo-tui-update m2 (list (cons 'type 'key) (cons 'key "b"))))
       (m4
        (logo-tui-update m3 (list (cons 'type 'key) (cons 'key "backspace")))))
  (assert-equal "å" (logo-model-input m2) "multi-byte key types one char")
  (assert-equal "åb" (logo-model-input m3)
   "typing after a multi-byte char appends")
  (assert-equal "å" (logo-model-input m4)
   "backspace deletes the whole multi-byte char"))

;; Submitting non-ASCII text evaluates it unchanged
(let* ((m
        (logo-model-with-input (logo-model-make) "PRINT \"blåbær\""))
       (m2 (logo-tui-update m (list (cons 'type 'key) (cons 'key "return")))))
  (assert-true (member "blåbær" (logo-model-transcript m2))
   "submit prints non-ASCII text"))

;; Return submits: input executed, transcript updated, input cleared
(let* ((m (logo-model-make))
       (m2 (logo-model-with-input m "FD 50 PRINT \"tui\""))
       (m3 (logo-tui-update m2 (list (cons 'type 'key) (cons 'key "return"))))
       (turtle (logo-interp-turtle (logo-model-state m3))))
  (assert-equal "" (logo-model-input m3) "submit clears input")
  (assert-equal 1 (length (canvas-segments (turtle-canvas turtle)))
   "submit draws")
  (assert-true (member "tui" (logo-model-transcript m3))
   "submit appends transcript"))

;; History: up walks older entries, up again clamps at the oldest,
;; down walks newer, and down past the newest clears the input.
(let* ((m (logo-model-make))
       (m (logo-model-with m 'history (list "FD 20" "FD 10")))
       (m1 (logo-tui-history m 1))
       (m2 (logo-tui-history m1 1))
       (m3 (logo-tui-history m2 1))
       (m4 (logo-tui-history m3 -1))
       (m5 (logo-tui-history m4 -1)))
  (assert-equal "FD 20" (logo-model-input m1) "history up gives newest")
  (assert-equal "FD 10" (logo-model-input m2) "history up again gives older")
  (assert-equal "FD 10" (logo-model-input m3) "history up clamps at oldest")
  (assert-equal "FD 20" (logo-model-input m4) "history down gives newer")
  (assert-equal "" (logo-model-input m5) "history down past newest clears"))

;; View renders a list of lines without error (headless: app-screen-size is nil)
(let ((lines (logo-tui-view (logo-model-make))))
  (assert-true (> (length lines) 5) "view returns lines")
  (assert-true (string-contains? (car lines) "Logo") "view header names Logo"))

;; The view follows Tapestry's row contract: no embedded newlines, every
;; row fits the screen width, and the command line stays the last row even
;; when the screen is too short for the usual transcript. Tapestry drops
;; rows past the bottom and repaints only the rows that changed.
(let ((lines (logo-tui-view (logo-model-make) (cons 24 80))))
  (assert-equal 0
   (length (filter (lambda (line) (string-contains? line "\n")) lines))
   "view rows contain no newlines")
  (assert-equal 0
   (length
    (filter (lambda (line) (> (tapestry:display-width line) 80)) lines))
   "view rows fit the screen width")
  (assert-true
   (string-prefix? "? " (tapestry:strip-ansi (car (reverse lines))))
   "the command line is the last view row"))
(let ((lines (logo-tui-view (logo-model-make) (cons 10 40))))
  (assert-true (<= (length lines) 10)
   "a short screen keeps every view row on screen")
  (assert-true
   (string-prefix? "? " (tapestry:strip-ansi (car (reverse lines))))
   "a short screen keeps the command line"))

;; ---------------------------------------------------------------------------
;; Mikro-Logo editor
;; ---------------------------------------------------------------------------
(defun tui-key (m key)
  (logo-tui-update m (list (cons 'type 'key) (cons 'key key))))

(defun tui-type (m text)
  (let loop ((i 0)
             (m m))
    (if (>= i (length text))
      m
      (loop (+ i 1) (tui-key m (substring text i (+ i 1)))))))

(defun tui-enter (m text)
  (tui-key (tui-type m text) "return"))

;; ---------------------------------------------------------------------------
;; Command line cursor editing (manual §3)
;; ---------------------------------------------------------------------------
(let* ((m (logo-model-with-input (logo-model-make) "frem 100")))
  (assert-equal 8 (logo-model-cursor m)
   "the command line cursor starts at the end")
  (let* ((m1 (tui-key m "left"))
         (m2 (tui-key m1 "home"))
         (m3 (tui-key m2 "end"))
         (m4 (tui-key m3 "right")))
    (assert-equal 7 (logo-model-cursor m1) "left moves the cursor one place")
    (assert-equal 0 (logo-model-cursor m2) "home goes to the start of the line")
    (assert-equal 8 (logo-model-cursor m3) "end goes to the end of the line")
    (assert-equal 8 (logo-model-cursor m4) "right clamps at the end")))
(let* ((m (logo-model-with-input (logo-model-make) "frem 100"))
       (m1 (tui-key (tui-key m "left") "left"))
       (m2 (tui-key m1 "3")))
  (assert-equal "frem 1300" (logo-model-input m2)
   "typing inserts at the cursor, not at the end")
  (assert-equal 7 (logo-model-cursor m2) "typing advances the cursor"))
(let* ((m (logo-model-with-input (logo-model-make) "frem 100"))
       (m1 (tui-key (tui-key (tui-key m "left") "left") "backspace")))
  (assert-equal "frem 00" (logo-model-input m1)
   "backspace deletes the character left of the cursor")
  (assert-equal 5 (logo-model-cursor m1) "backspace moves the cursor left"))
(let* ((m (logo-model-with-input (logo-model-make) "frem 100"))
       (m1 (tui-key (tui-key m "home") "delete")))
  (assert-equal "rem 100" (logo-model-input m1)
   "Delete removes the character under the cursor"))
(let* ((m (logo-model-with-input (logo-model-make) "frem 100"))
       (m1 (tui-key (tui-key m "home") "insert")))
  (assert-equal " frem 100" (logo-model-input m1)
   "Insert shifts the line right and inserts a blank")
  (assert-equal 1 (logo-model-cursor m1)
   "Insert leaves the cursor after the blank"))
(let* ((m (logo-model-with-input (logo-model-make) "frem 100"))
       (m1 (tui-key (tui-key m "home") "C-k")))
  (assert-equal "" (logo-model-input m1) "C-k deletes the rest of the line")
  (assert-equal 0 (logo-model-cursor m1) "C-k leaves the cursor in place"))

;; Return executes the whole line whatever the cursor position.
(let* ((m (logo-model-with-input (logo-model-make) "FD 50"))
       (m1 (tui-key m "return"))
       (m2 (tui-key m1 "return"))
       (turtle (logo-interp-turtle (logo-model-state m2))))
  (assert-equal 1 (length (canvas-segments (turtle-canvas turtle)))
   "Return executes the whole line regardless of the cursor")
  (assert-equal "" (logo-model-input m2) "Return clears the line")
  (assert-equal 0 (logo-model-cursor m2) "Return resets the cursor"))
(let* ((m (logo-model-with-input (logo-model-make) "frem 100"))
       (m1 (tui-key m "escape")))
  (assert-equal "" (logo-model-input m1) "Escape clears the command line")
  (assert-equal 0 (logo-model-cursor m1) "Escape resets the cursor"))

;; Mikro mode: up/down are start/end of line, not history (manual §3).
(let* ((m (logo-model-with-input (logo-model-make 'mikro) "frem 100"))
       (m1 (logo-model-with m 'history (list "frem 10")))
       (m2 (tui-key m1 "up"))
       (m3 (tui-key m2 "down")))
  (assert-equal "frem 100" (logo-model-input m2)
   "up in Mikro mode does not recall history")
  (assert-equal 0 (logo-model-cursor m2) "up goes to the start of the line")
  (assert-equal 8 (logo-model-cursor m3) "down goes to the end of the line"))

;; The English dialect keeps up/down for history and still edits mid-line.
(let* ((m (logo-model-with-input (logo-model-make 'logo) "frem 100"))
       (m1 (logo-model-with m 'history (list "frem 10")))
       (m2 (tui-key m1 "up")))
  (assert-equal "frem 10" (logo-model-input m2)
   "up keeps recalling history in the English dialect")
  (assert-equal 7 (logo-model-cursor m2)
   "a recalled history line puts the cursor at its end")
  (let* ((m3 (tui-key m "left")))
    (assert-equal 7 (logo-model-cursor m3)
     "left edits the line in the English dialect too")))

;; F1 recalls the previous sentence line and skips command lines (manual §3).
(let* ((m (logo-model-with-input (logo-model-make 'mikro) ""))
       (m
        (logo-model-with m 'history
         (list "frem 20" "lær" "frem 10" "ret polygon")))
       (m1 (tui-key m "f1"))
       (m2 (tui-key m1 "f1"))
       (m3 (tui-key m2 "f1")))
  (assert-equal "frem 20" (logo-model-input m1)
   "F1 recalls the newest sentence line")
  (assert-equal "frem 10" (logo-model-input m2)
   "F1 walks back past command lines")
  (assert-equal "frem 10" (logo-model-input m3)
   "F1 stops at the oldest sentence line")
  (assert-equal 7 (logo-model-cursor m2)
   "a recalled line has the cursor at its end"))

;; The Mikro command line starts with LOGO> (manual §3); the English one
;; keeps ?. Both render an inverse-video block cursor.
(let* ((mikro
        (logo-tui-view (logo-model-with-input (logo-model-make 'mikro) "frem")))
       (logo-view
        (logo-tui-view (logo-model-with-input (logo-model-make 'logo) "FD")))
       (mikro-line (car (reverse mikro)))
       (logo-line (car (reverse logo-view))))
  (assert-true (string-contains? mikro-line "LOGO> ")
   "the Mikro command line starts with LOGO>")
  (assert-true (string-contains? logo-line "? ")
   "the English command line keeps the ? prompt")
  (assert-true (string-contains? mikro-line (tapestry:reverse-video))
   "the command line renders a block cursor")
  (assert-true (string-contains? logo-line (tapestry:reverse-video))
   "the English command line renders a block cursor"))

;; Long input scrolls so the block cursor stays visible.
(let* ((long (make-string 40 #\x))
       (m (logo-model-with-input (logo-model-make 'mikro) long))
       (line (logo-tui-command-line-view m 20)))
  (assert-equal 20 (length (tapestry:strip-ansi line))
   "the command line is clipped to the screen width")
  (assert-true (not (string-contains? line "LOGO> "))
   "the scrolled command line hides the off-screen prompt"))
(let* ((logo-model (logo-model-make 'logo))
       (logo-f5 (tui-key logo-model "f5")))
  (assert-equal nil (logo-model-editor logo-f5)
   "F5 does nothing in the English dialect"))
(let* ((m (logo-model-make 'mikro))
       (m1 (tui-enter m "lær")))
  (assert-true (not (null? (logo-model-editor m1)))
   "the lowercase command word lær opens the editor"))
(let* ((m (logo-model-make 'mikro))
       (m1 (tui-key m "f5"))
       (editor (logo-model-editor m1)))
  (assert-true (not (null? editor)) "F5 opens the editor in Mikro mode")
  (assert-equal "begynd " (car (logo-editor-lines editor))
   "LÆR starts with BEGYND")
  (assert-equal 24 (length (logo-tui-view m1))
   "editor view fills a 24-row screen")
  (assert-true
   (string-contains? (list-ref (logo-tui-view m1) 22) "A4")
   "editor status line names A4")
  (let ((short (logo-tui-view m1 (cons 10 40))))
    (assert-equal 10 (length short) "editor view fills a short screen")
    (assert-true
     (string-prefix? "LOGO> " (tapestry:strip-ansi (car (reverse short))))
     "the editor keeps its command line")))

;; Type a complete procedure, A4, then run it.
(let* ((m (logo-model-make 'mikro))
       (m1 (tui-enter (tui-key m "f5") "polygon side antal"))
       (m2 (tui-enter m1 "frem side"))
       (m3 (tui-key m2 "C-s")))
  (assert-equal nil (logo-model-editor m3) "A4 closes the editor")
  (assert-equal nil (logo-model-message m3) "successful compile has no message")
  (assert-true
   (not (null? (hash-ref (logo-interp-procs (logo-model-state m3)) "POLYGON")))
   "A4 installs the procedure")
  (assert-equal
   '("begynd polygon side antal" "   frem side" "slut")
   (logo-interp-procedure-source (logo-model-state m3) "POLYGON")
   "A4 stores canonical indented source")
  (assert-equal nil (logo-interp-blocked (logo-model-state m3))
   "successful compile clears the block")
  (let* ((m4 (tui-enter (logo-model-with-input m3 "") "polygon 30 4"))
         (turtle (logo-interp-turtle (logo-model-state m4))))
    (assert-equal 1 (length (canvas-segments (turtle-canvas turtle)))
     "the compiled procedure runs from the command line")))

;; RET reopens stored source; ESC abandons without changing it.
(let* ((m (logo-model-make 'mikro))
       (m1 (tui-enter (tui-key m "f5") "polygon side antal"))
       (m2 (tui-enter m1 "frem side"))
       (m3 (tui-key m2 "C-s"))
       (m4 (tui-enter (logo-model-with-input m3 "") "ret polygon"))
       (editor (logo-model-editor m4)))
  (assert-true (not (null? editor)) "RET opens an existing procedure")
  (assert-equal "   frem side" (list-ref (logo-editor-lines editor) 1)
   "RET shows canonical indented source")
  (let* ((m5 (tui-key m4 "escape")))
    (assert-equal nil (logo-model-editor m5) "ESC closes the editor")
    (assert-equal
     '("begynd polygon side antal" "   frem side" "slut")
     (logo-interp-procedure-source (logo-model-state m5) "POLYGON")
     "ESC leaves the stored source intact")))

;; A compile error returns to the command line, blocks procedures, and keeps
;; the draft for RET.
(let* ((m (logo-model-make 'mikro))
       (m1 (tui-enter (tui-key m "f5") "polygon side antal"))
       (m2 (tui-enter m1 "frem side"))
       (m3 (tui-key m2 "C-s"))
       (m4 (tui-enter (logo-model-with-input m3 "") "ret polygon"))
       (m5 (tui-key m4 "down"))
       (m6 (tui-key m5 "end"))
       (m7 (tui-key m6 "backspace"))
       (m8 (tui-key m7 "backspace"))
       (m9 (tui-key m8 "backspace"))
       (m10 (tui-key m9 "backspace"))
       (m11 (tui-key m10 "C-s")))
  (assert-equal nil (logo-model-editor m11)
   "failed compile returns to the command line")
  (assert-equal "Navn eller tal mangler" (logo-model-message m11)
   "failed compile reports in the message line")
  (assert-true (not (null? (logo-interp-blocked (logo-model-state m11))))
   "failed compile blocks procedure execution")
  (assert-true (not (null? (logo-model-draft m11)))
   "failed compile keeps the draft")
  (assert-equal "POLYGON" (logo-model-draft-name m11)
   "the draft remembers its procedure name")
  (let* ((m12 (tui-enter (logo-model-with-input m11 "") "polygon 10 4"))
         (turtle (logo-interp-turtle (logo-model-state m12))))
    (assert-equal 0 (length (canvas-segments (turtle-canvas turtle)))
     "blocked procedures do not run")
    (assert-true
     (member "Error: Navn eller tal mangler" (logo-model-transcript m12))
     "blocked execution reports the compile error"))
  (let* ((m12 (tui-enter (logo-model-with-input m11 "") "ret polygon"))
         (editor (logo-model-editor m12)))
    (assert-true (not (null? editor)) "RET reopens the failed draft")
    (assert-equal "   frem " (list-ref (logo-editor-lines editor) 1)
     "the reopened draft has the failed text")))

;; Bare RET prompts for a procedure name.
(let* ((m (logo-model-make 'mikro))
       (defined (tui-key (tui-enter (tui-key m "f5") "p") "C-s"))
       (m1 (tui-enter defined "ret")))
  (assert-equal 'ret-name (logo-model-prompt m1) "bare RET prompts for a name")
  (let* ((m2 (tui-enter m1 "p")))
    (assert-equal nil (logo-model-prompt m2) "the prompt is cleared")
    (assert-true (not (null? (logo-model-editor m2)))
     "a name after the RET prompt opens the editor")
    (assert-equal nil (logo-model-editor (tui-key m2 "escape"))
     "ESC closes the editor opened from the prompt")))

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
