;; test-math.lisp - Tests for the pure-Lisp math module
(define *test-dir* (or (file-name-directory *load-pathname*) ""))

(set! *load-path* (cons (concat *test-dir* "../lisp/") *load-path*))

(require 'logo)

(use-package 'logo)

(define passed 0)

(define failed 0)

(defun assert-close (expected actual tolerance description)
  (if (< (logo-abs (- expected actual)) tolerance)
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

;; abs
(assert-equal 5 (logo-abs -5) "abs of negative")
(assert-equal 5 (logo-abs 5) "abs of positive")
(assert-equal 0 (logo-abs 0) "abs of zero")

;; sqrt
(assert-close 2.0 (logo-sqrt 4.0) 0.0001 "sqrt 4")
(assert-close 1.41421356 (logo-sqrt 2.0) 0.00001 "sqrt 2")

(assert-equal 0 (logo-sqrt 0) "sqrt 0")

;; sin/cos at cardinal points
(assert-close 0.0 (logo-sin 0.0) 0.000001 "sin 0")
(assert-close 1.0 (logo-sin (/ logo-pi 2)) 0.000001 "sin pi/2")
(assert-close 0.0 (logo-sin logo-pi) 0.000001 "sin pi")
(assert-close 1.0 (logo-cos 0.0) 0.000001 "cos 0")
(assert-close 0.0 (logo-cos (/ logo-pi 2)) 0.000001 "cos pi/2")
(assert-close -1.0 (logo-cos logo-pi) 0.000001 "cos pi")
;; sin^2 + cos^2 = 1 at an arbitrary angle
(assert-close 1.0
 (+ (* (logo-sin 1.234) (logo-sin 1.234))
  (* (logo-cos 1.234) (logo-cos 1.234)))
 0.000001 "sin^2+cos^2=1")
;; large angle range reduction: sin(100*pi) ~ 0
(assert-close 0.0 (logo-sin (* 100 logo-pi)) 0.000001 "sin 100pi")

;; degrees <-> radians
(assert-close 180.0 (logo-rad->deg logo-pi) 0.000001 "rad->deg pi")
(assert-close 90.0 (logo-rad->deg (/ logo-pi 2)) 0.000001 "rad->deg pi/2")
(assert-close logo-pi (logo-deg->rad 180.0) 0.000001 "deg->rad 180")

;; heading normalization
(assert-equal 90 (logo-normalize-heading 450) "normalize 450")
(assert-equal 270 (logo-normalize-heading -90) "normalize -90")
(assert-equal 0 (logo-normalize-heading 360) "normalize 360")

;; random: in range and (with fixed seed) reproducible
(logo-srand 42)

(define *first-random* (logo-random))

(assert-equal #t (and (>= *first-random* 0) (< *first-random* 1))
 "random in [0,1)")

(logo-srand 42)

(assert-equal #t (< (logo-abs (- *first-random* (logo-random))) 0.0000001)
 "random reproducible")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
