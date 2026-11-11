;; test-interpreter.lisp - Tests for the Logo evaluator
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

(defun assert-close (expected actual tolerance description)
  (if (< (abs (- expected actual)) tolerance)
    (progn (format #t "PASS: ~a~%" description) (set! passed (+ passed 1)))
    (progn
      (format #t "FAIL: ~a (expected ~a, got ~a)~%" description expected actual)
      (set! failed (+ failed 1)))))

(defun run-turtle (source)
  "Run SOURCE, return the final turtle."
  (logo-interp-turtle (logo-run source)))

;; Motion: FD north from origin
(let ((t (run-turtle "FD 100")))
  (assert-close 0.0 (turtle-x t) 0.001 "FD 100 x=0")
  (assert-close 100.0 (turtle-y t) 0.001 "FD 100 y=100")
  (assert-equal 1 (length (canvas-segments (turtle-canvas t)))
   "FD draws 1 segment"))

;; Motion: RT then FD moves east
(let ((t (run-turtle "RT 90 FD 50")))
  (assert-close 50.0 (turtle-x t) 0.001 "RT 90 FD 50 x=50")
  (assert-close 0.0 (turtle-y t) 0.001 "RT 90 FD 50 y=0")
  (assert-equal 90 (turtle-heading t) "heading after RT 90"))

;; Motion: BK moves backwards
(let ((t (run-turtle "BK 30")))
  (assert-close -30.0 (turtle-y t) 0.001 "BK 30 y=-30"))

;; Pen up: no segment
(let ((t (run-turtle "PU FD 100 PD FD 100")))
  (assert-equal 1 (length (canvas-segments (turtle-canvas t)))
   "PU suppresses segment"))

;; Square closes: REPEAT 4 [FD 100 RT 90] returns to origin
(let ((t (run-turtle "REPEAT 4 [FD 100 RT 90]")))
  (assert-equal 4 (length (canvas-segments (turtle-canvas t)))
   "square has 4 segments")
  (assert-close 0.0 (turtle-x t) 0.001 "square closes x")
  (assert-close 0.0 (turtle-y t) 0.001 "square closes y"))

;; CS clears the canvas but keeps the turtle
(let ((t (run-turtle "FD 100 CS")))
  (assert-equal 0 (length (canvas-segments (turtle-canvas t)))
   "CS clears segments")
  (assert-close 100.0 (turtle-y t) 0.001 "CS keeps position"))

;; TO with a parameter
(let ((t (run-turtle "TO SQUARE :S REPEAT 4 [FD :S RT 90] END SQUARE 50")))
  (assert-equal 4 (length (canvas-segments (turtle-canvas t)))
   "TO SQUARE draws")
  (assert-close 0.0 (turtle-x t) 0.001 "TO SQUARE closes"))

;; OUTPUT: recursive factorial via a procedure returning a value
(let ((t
       (run-turtle
        "TO FACT :N IF GREATER? :N 1 [OUTPUT PRODUCT [:N FACT DIFFERENCE :N 1]] OUTPUT 1 END PRINT FACT 5")))
  (assert-equal '("120") (turtle-output t) "factorial 5 = 120"))

;; MAKE / THING
(let ((t (run-turtle "MAKE :X 42 PRINT THING :X")))
  (assert-equal '("42") (turtle-output t) "MAKE/THING"))

;; IF takes the true branch
(let ((t (run-turtle "IF PENDOWNP [FD 10]")))
  (assert-close 10.0 (turtle-y t) 0.001 "IF true branch runs"))

;; IFELSE takes the false branch (pen is up)
(let ((t (run-turtle "PU IFELSE PENDOWNP [FD 10] [FD 20]")))
  (assert-close 20.0 (turtle-y t) 0.001 "IFELSE false branch runs"))

;; PRINT transcript
(let ((t (run-turtle "PRINT \"hello\" PRINT 42")))
  (assert-equal '("hello" "42") (turtle-output t) "PRINT transcript"))

;; RUN executes a bracketed instruction list
(let ((t (run-turtle "RUN [FD 10 RT 90 FD 10]")))
  (assert-equal 2 (length (canvas-segments (turtle-canvas t)))
   "RUN draws 2 segments"))

;; Arithmetic queries: delegated to Ditty's numeric builtins
(assert-equal '("3") (turtle-output (run-turtle "PRINT QUOTIENT 7 2"))
 "QUOTIENT truncates")
(assert-equal '("3") (turtle-output (run-turtle "PRINT QUOTIENT 7.5 2"))
 "QUOTIENT truncates floats")
(assert-equal '("-1") (turtle-output (run-turtle "PRINT REMAINDER -7 2"))
 "REMAINDER takes the dividend's sign")
(assert-equal '("1") (turtle-output (run-turtle "PRINT MODULO -7 2"))
 "MODULO takes the divisor's sign")
(assert-equal '("5") (turtle-output (run-turtle "PRINT ABS -5")) "ABS")
(assert-equal '("0") (turtle-output (run-turtle "PRINT RANDOM 1"))
 "RANDOM 1 is 0")

(assert-true (error? (logo-run "PRINT RANDOM 0"))
 "RANDOM 0 is an error value")

;; Errors are values: logo-run / logo-run-file return error objects
;; (which the CLI reports) instead of raising uncaught Ditty errors.
(assert-true (error? (logo-run "WIBBLE 3"))
 "logo-run unknown word is error value")
(assert-true (error? (logo-run "FD"))
 "logo-run missing argument is error value")
(assert-true (error? (logo-run-file "/nonexistent-logo-file.logo"))
 "logo-run-file missing file is error value")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
