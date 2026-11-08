;; test-canvas.lisp - Tests for the canvas and Braille renderer
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

;; Canvas basics
(let* ((c (canvas-make 100 100))
       (c2 (canvas-add-segment c 0 0 10 10 nil)))
  (assert-equal 0 (length (canvas-segments c)) "empty canvas has no segments")
  (assert-equal 1 (length (canvas-segments c2)) "add-segment appends")
  (assert-equal 0 (length (canvas-segments c)) "add-segment is functional"))

;; Bounds
(let* ((c (canvas-add-segment (canvas-make 200 200) -10 -20 30 40 nil)))
  (assert-equal '(-10 -20 30 40) (canvas-bounds c) "bounds of one segment"))

(assert-equal nil (canvas-bounds (canvas-make 10 10)) "bounds of empty canvas")

;; Rasterize: horizontal line through the centre sets centre-row pixels
(let* ((c (canvas-add-segment (canvas-make 100 100) -50 0 50 0 nil))
       (g (canvas-rasterize c 20 20))
       (centre-row (vector-ref g 10)))
  (assert-equal 1 (vector-ref centre-row 10) "centre pixel set")
  (assert-equal 1 (vector-ref centre-row 0) "left edge pixel set")
  (assert-equal 1 (vector-ref centre-row 19) "right edge pixel set")
  (assert-equal 0 (vector-ref (vector-ref g 0) 10) "top row empty"))

;; Rasterize: diagonal line sets pixels at both ends (Bresenham terminates)
(let* ((c (canvas-add-segment (canvas-make 100 100) -50 -50 50 50 nil))
       (g (canvas-rasterize c 20 20)))
  (assert-equal 1 (vector-ref (vector-ref g 19) 0) "diagonal bottom-left set")
  (assert-equal 1 (vector-ref (vector-ref g 0) 19) "diagonal top-right set"))

;; Braille output: correct shape, and a vertical line produces braille
(let* ((c (canvas-add-segment (canvas-make 100 100) 0 -50 0 50 nil))
       (lines (canvas->braille-lines c 10 5)))
  (assert-equal 5 (length lines) "braille line count")
  (assert-equal 10 (length (car lines)) "braille line is 10 codepoints")
  ;; The vertical line should make at least one cell non-blank (not U+2800)
  (assert-equal #t
   (not (equal? (car lines) "⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀"))
   "vertical line renders non-blank braille"))

;; Braille output: empty canvas is all blank braille (U+2800)
(let ((lines (canvas->braille-lines (canvas-make 10 10) 4 2)))
  (assert-equal '("⠀⠀⠀⠀" "⠀⠀⠀⠀") lines "empty canvas is blank braille"))

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
