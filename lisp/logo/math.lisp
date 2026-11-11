;; math.lisp - Constants and angle helpers for Logo
;;
;; Ditty Lisp (0.8+) supplies the numerics this interpreter used to
;; hand-roll: abs, sqrt, sin, cos, atan, expt, float, round, truncate,
;; ceiling, unary/float-aware floor, quotient, remainder, modulo,
;; random and random-seed. Logo code calls those directly; there are no
;; logo-* aliases. What remains here is the Logo-specific angle
;; convention: headings are degrees, clockwise from north.
;;
;;   logo-pi                 the circle constant
;;   logo-deg->rad           degrees -> radians
;;   logo-rad->deg           radians -> degrees
;;   logo-normalize-heading  wrap a heading into [0, 360)
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-math)

(define logo-pi 3.141592653589793)

(defun logo-deg->rad (deg)
  "Convert degrees to radians."
  (/ (* deg logo-pi) 180.0))

(defun logo-rad->deg (rad)
  "Convert radians to degrees."
  (/ (* rad 180.0) logo-pi))

(defun logo-normalize-heading (h)
  "Normalize heading H (degrees) into [0, 360)."
  (modulo h 360))
