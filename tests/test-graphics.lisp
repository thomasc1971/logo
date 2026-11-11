;; test-graphics.lisp - Tests for graphics backends and capability detection
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

;; Capability detection always offers the canvas backend
(let ((caps (logo-graphics-capabilities)))
  (assert-true (cdr (assoc 'canvas caps)) "canvas capability present")
  (assert-true (member (logo-graphics-backend) '(canvas sixel kitty iterm2))
   "backend is a known symbol"))

;; Pure translation from a Ditty capabilities alist (as delivered by the
;; TUI's `capabilities` message, or by the headless env-only fallback)
(define *fake-caps*
  (list (cons 'sixel #t) (cons 'kitty-graphics nil) (cons 'iterm2-images nil)
   (cons 'kitty-keyboard 1) (cons 'pixel-size (cons 800 600))
   (cons 'cell-size (cons 10 20)) (cons 'source "query")))

(define *empty-caps*
  (list (cons 'sixel nil) (cons 'kitty-graphics nil) (cons 'iterm2-images nil)
   (cons 'kitty-keyboard nil) (cons 'pixel-size nil) (cons 'cell-size nil)
   (cons 'source "none")))

(let ((caps (logo-graphics-capabilities-from *fake-caps*)))
  (assert-equal 'sixel (logo-graphics-backend-from *fake-caps*)
   "backend-from picks sixel")
  (assert-equal #t (cdr (assoc 'sixel caps)) "capabilities-from maps sixel")
  (assert-equal #f (cdr (assoc 'kitty caps)) "capabilities-from maps kitty")
  (assert-equal #t (cdr (assoc 'canvas caps)) "capabilities-from keeps canvas"))

(assert-equal (cons 10 20) (logo-graphics-cell-size *fake-caps*)
 "cell size comes from cell-size")
(assert-equal (cons 800 600) (logo-graphics-pixel-size *fake-caps*)
 "pixel size comes from pixel-size")
(assert-equal nil (logo-graphics-cell-size *empty-caps*)
 "cell size is nil when unreported")
(assert-equal 'canvas (logo-graphics-backend-from *empty-caps*)
 "backend-from falls back to canvas")

;; Sixel encoder: DCS intro, Pan/Pad raster attributes, ST terminator
;; (exact substring comparisons; string-prefix? would also work)
(let* ((c (canvas-add-segment (canvas-make 100 100) -50 -50 50 50 nil))
       (sixel (logo-render-sixel c 60 60)))
  (assert-equal "\033P" (substring sixel 0 2) "sixel starts with DCS")
  (assert-true (string-contains? sixel "\"1;1;60;60")
   "sixel has Pan/Pad 60x60")
  (assert-true (string-contains? sixel "#1;2;100;100;100")
   "sixel defines palette colour 1")
  (assert-equal "\033\\" (substring sixel (- (length sixel) 2))
   "sixel ends with ST"))

;; logo-render dispatch
(let* ((c (canvas-add-segment (canvas-make 100 100) 0 0 0 50 nil)))
  (assert-equal 5 (length (logo-render c 'canvas 10 5)) "render canvas lines")
  (assert-equal "\033P" (substring (logo-render c 'sixel 10 5) 0 2)
   "render sixel dispatch")
  (assert-equal nil (logo-render c 'kitty 10 5) "render kitty is planned (nil)")
  (assert-equal nil (logo-render c 'iterm2 10 5)
   "render iterm2 is planned (nil)"))

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
