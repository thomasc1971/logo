;; test-examples.lisp - Run every example program headlessly
(define *test-dir* (or (file-name-directory *load-pathname*) ""))

(set! *load-path* (cons (concat *test-dir* "../lisp/") *load-path*))

(require 'logo)

(use-package 'logo)

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

;; Every example file parses, runs, draws segments, and prints its
;; "<name> done" transcript line.
(let ((examples
       '("square.logo" "house.logo" "spiral.logo" "star.logo" "circle.logo")))
  (let loop ((rest examples))
    (if (null? rest)
      nil
      (let* ((name (car rest))
             (path (concat *test-dir* "../examples/" name))
             (state (logo-run-file path))
             (turtle (logo-interp-turtle state))
             (segs (canvas-segments (turtle-canvas turtle)))
             (output (turtle-output turtle)))
        (assert-true (> (length segs) 0) (concat name " draws segments"))
        (assert-true (> (length output) 0) (concat name " prints transcript"))
        ;; Rendering the picture must not error
        (let ((lines (canvas->braille-lines (turtle-canvas turtle) 40 10)))
          (assert-equal 10 (length lines) (concat name " renders 10 lines")))
        (loop (cdr rest))))))

;; Headless REPL evaluation: logo-repl-eval returns state + transcript lines
(let* ((state (logo-interp-make 200 200))
       (result (logo-repl-eval state "FD 10 PRINT \"hi\"")))
  (assert-equal '("hi") (cdr result) "repl-eval transcript")
  (assert-equal 1
   (length (canvas-segments (turtle-canvas (logo-interp-turtle (car result)))))
   "repl-eval draws"))

;; REPL errors are reported as transcript lines, not thrown
(let ((result (logo-repl-eval (logo-interp-make 200 200) "WIBBLE 3")))
  (assert-true (> (length (cdr result)) 0) "repl-eval reports errors as lines"))

;; REPL transcript lines are only the NEW lines: the turtle accumulates
;; all PRINT output, but each repl-eval must not re-emit previous lines
;; (the TUI would otherwise duplicate every PRINT on every submit).
(let* ((r1 (logo-repl-eval (logo-interp-make 200 200) "PRINT 1"))
       (r2 (logo-repl-eval (car r1) "PRINT 2"))
       (r3 (logo-repl-eval (car r2) "FD 10")))
  (assert-equal '("1") (cdr r1) "repl-eval first PRINT")
  (assert-equal '("2") (cdr r2) "repl-eval does not re-emit earlier PRINTs")
  (assert-equal nil (cdr r3) "repl-eval with no PRINT returns no lines")
  (assert-equal '("1" "2")
   (turtle-output (logo-interp-turtle (car r3)))
   "turtle output still accumulates"))

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
