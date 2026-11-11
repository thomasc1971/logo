;; test-math.lisp - Tests for the math module and Ditty's numeric builtins
;;
;; Logo no longer implements the numerics itself: abs, sqrt, sin, cos,
;; expt, floor, quotient/remainder/modulo, random and random-seed come
;; from Ditty (0.8+). This file covers the Logo-specific angle helpers
;; and pins the upstream behaviour Logo relies on.
(define *test-dir* (or (file-name-directory *load-pathname*) ""))

(set! *load-path* (cons (concat *test-dir* "../lisp/") *load-path*))

(require 'logo)

(use-package 'logo)

(define passed 0)

(define failed 0)

(defun assert-close (expected actual tolerance description)
  (if (< (abs (- expected actual)) tolerance)
    (progn (format #t "PASS: ~a~%" description) (set! passed (+ passed 1)))
    (progn
      (format #t "FAIL: ~a (expected ~a, got ~a)~%" description expected actual)
      (set! failed (+ failed 1)))))

(defun assert-equal (expected actual description)
  (if (equal? expected actual)
    (progn (format #t "PASS: ~a~%" description) (set! passed (+ passed 1)))
    (progn (format #t "FAIL: ~a~%" description)
      (format #t "  Expected: ~s~%" expected)
      (format #t "  Actual:   ~s~%" actual)
      (set! failed (+ failed 1)))))

(defun assert-true (actual description)
  (assert-equal #t (if actual #t #f) description))

;; ---------------------------------------------------------------------------
;; Logo angle helpers
;; ---------------------------------------------------------------------------

;; degrees <-> radians
(assert-close 180.0 (logo-rad->deg logo-pi) 0.000001 "rad->deg pi")
(assert-close 90.0 (logo-rad->deg (/ logo-pi 2)) 0.000001 "rad->deg pi/2")
(assert-close logo-pi (logo-deg->rad 180.0) 0.000001 "deg->rad 180")
(assert-close 0.0 (logo-deg->rad 0.0) 0.000001 "deg->rad 0")

;; heading normalization
(assert-equal 90 (logo-normalize-heading 450) "normalize 450")
(assert-equal 270 (logo-normalize-heading -90) "normalize -90")
(assert-equal 0 (logo-normalize-heading 360) "normalize 360")

;; ---------------------------------------------------------------------------
;; Ditty numeric contract (Logo calls these directly)
;; ---------------------------------------------------------------------------
(assert-equal 5 (abs -5) "abs of negative")
(assert-equal 5 (abs 5) "abs of positive")
(assert-equal 0 (abs 0) "abs of zero")

(assert-close 4.0 (sqrt 16) 0.000001 "sqrt 16")
(assert-close 1.41421356 (sqrt 2) 0.000001 "sqrt 2")
(assert-close 0.0 (sin 0.0) 0.000001 "sin 0")
(assert-close 1.0 (sin (/ logo-pi 2)) 0.000001 "sin pi/2")
(assert-close 0.0 (sin logo-pi) 0.000001 "sin pi")
(assert-close 1.0 (cos 0.0) 0.000001 "cos 0")
(assert-close 0.0 (cos (/ logo-pi 2)) 0.000001 "cos pi/2")
(assert-close -1.0 (cos logo-pi) 0.000001 "cos pi")
(assert-close 1.0
 (+ (* (sin 1.234) (sin 1.234)) (* (cos 1.234) (cos 1.234)))
 0.000001 "sin^2+cos^2=1")

(assert-equal 1024 (expt 2 10) "expt 2^10")
(assert-equal 7 (floor 7.5) "floor 7.5")
(assert-equal -8 (floor -7.5) "floor -7.5")

(assert-true (integer? (floor 7.5)) "floor returns an integer")

(assert-equal 3 (quotient 7.5 2) "quotient truncates floats")

(assert-close 1.5 (remainder 7.5 2) 0.000001
 "remainder keeps the dividend sign")
(assert-close 0.5 (modulo -7.5 2) 0.000001 "modulo keeps the divisor sign")

;; random: integer range, float range, reproducible with a seed
(assert-equal 0 (random 1) "random 1 is 0")

(assert-true (and (>= (random 10) 0) (< (random 10) 10))
 "random integer in range")
(assert-true (and (>= (random 1.0) 0.0) (< (random 1.0) 1.0))
 "random float in [0,1)")

(random-seed 42)

(define *first-random* (random 1000))

(random-seed 42)

(assert-equal *first-random* (random 1000) "same seed, same value")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
