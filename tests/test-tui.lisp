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
       (m2 (logo-model-with m 'input "FDX"))
       (m3
        (logo-tui-update m2 (list (cons 'type 'key) (cons 'key "backspace")))))
  (assert-equal "FD" (logo-model-input m3) "backspace deletes last char"))

;; Ditty decodes multi-byte input in the event parser, so a non-ASCII
;; letter arrives as a one-character key name and types as one character.
(let* ((m (logo-model-with (logo-model-make) 'input ""))
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
        (logo-model-with (logo-model-make) 'input "PRINT \"blåbær\""))
       (m2 (logo-tui-update m (list (cons 'type 'key) (cons 'key "return")))))
  (assert-true (member "blåbær" (logo-model-transcript m2))
   "submit prints non-ASCII text"))

;; Return submits: input executed, transcript updated, input cleared
(let* ((m (logo-model-make))
       (m2 (logo-model-with m 'input "FD 50 PRINT \"tui\""))
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

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
