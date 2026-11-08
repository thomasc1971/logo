;; math.lisp - Numbers and trigonometry for Logo
;;
;; Ditty Lisp has float literals and float arithmetic (+ - * /) but no
;; transcendental builtins (no sin/cos/sqrt/abs/expt). Turtle graphics needs
;; all of them, so they are implemented here in pure Lisp:
;;
;;   logo-abs, logo-sqrt   (Newton-Raphson)
;;   logo-sin, logo-cos     (Taylor series, range-reduced)
;;   logo-deg->rad, logo-rad->deg
;;   logo-random            (LCG; Ditty has no random builtin)
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-math)

(define logo-pi 3.141592653589793)

(define logo-2pi (* 2 logo-pi))

(defun logo-abs (x)
  "Absolute value of X (Ditty has no abs builtin)."
  (if (< x 0) (- 0 x) x))

(defun logo-sqrt (x)
  "Square root of X by Newton-Raphson iteration. X must be >= 0."
  (if (< x 0)
    (error (format nil "sqrt of negative number: ~a" x))
    (if (or (= x 0) (= x 1))
      x
      (let loop ((guess (/ x 2)))
        (let* ((next (/ (+ guess (/ x guess)) 2)))
          (if (< (logo-abs (- next guess)) 0.0000001)
            next
            (loop next)))))))

(defun logo-real-floor (x)
  "Greatest integer <= X, for float X.
   Ditty's floor truncates float arguments to integers before dividing,
   so (floor x 1) is truncation toward zero; adjust for negatives."
  (let* ((t (floor x 1)))
    (if (and (< x 0) (< x t))
      (- t 1)
      t)))

(defun logo-range-reduce (x)
  "Reduce X (radians) into [-pi, pi] via modulo 2*pi."
  (let* ((n (logo-real-floor (/ x logo-2pi)))
         (y (- x (* n logo-2pi))))
    (if (> y logo-pi)
      (- y logo-2pi)
      y)))

(defun logo-sin (x)
  "Sine of X (radians) via Taylor series. Accurate to ~1e-9.
   term_n = term_{n-1} * -x^2 / ((2n)(2n+1))."
  (let* ((x (logo-range-reduce x)))
    (let loop ((term x)
               (sum x)
               (n 1))
      (if (> n 12)
        sum
        (let* ((term2 (* term (/ (- (* x x)) (* (* 2 n) (+ (* 2 n) 1)))))
               (sum2 (+ sum term2)))
          (loop term2 sum2 (+ n 1)))))))

(defun logo-cos (x)
  "Cosine of X (radians) via Taylor series. Accurate to ~1e-9.
   term_n = term_{n-1} * -x^2 / ((2n-1)(2n))."
  (let* ((x (logo-range-reduce x)))
    (let loop ((term 1.0)
               (sum 1.0)
               (n 1))
      (if (> n 12)
        sum
        (let* ((term2 (* term (/ (- (* x x)) (* (- (* 2 n) 1) (* 2 n)))))
               (sum2 (+ sum term2)))
          (loop term2 sum2 (+ n 1)))))))

(defun logo-deg->rad (deg)
  "Convert degrees to radians."
  (/ (* deg logo-pi) 180.0))

(defun logo-rad->deg (rad)
  "Convert radians to degrees."
  (/ (* rad 180.0) logo-pi))

(defun logo-normalize-heading (h)
  "Normalize heading H (degrees) into [0, 360)."
  (let* ((r (modulo h 360)))
    (if (< r 0) (+ r 360) r)))

;; ---------------------------------------------------------------------------
;; Pseudo-random numbers (LCG; Ditty has no random builtin)
;; ---------------------------------------------------------------------------
(define *logo-rng-seed* 123456789)

(defun logo-srand (seed)
  "Seed the Logo random number generator with SEED."
  (set! *logo-rng-seed* (modulo seed 2147483647))
  *logo-rng-seed*)

(defun logo-random ()
  "Return the next pseudo-random float in [0, 1)."
  (set! *logo-rng-seed*
   (modulo (+ (* *logo-rng-seed* 1103515245) 12345) 2147483648))
  (/ *logo-rng-seed* 2147483648.0))
