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
