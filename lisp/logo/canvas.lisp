;; canvas.lisp - Drawing surface: segments, raster grid, Braille rendering
;;
;; A canvas is the terminal-independent record of everything the turtle has
;; drawn. It knows nothing about Logo and nothing about the terminal:
;; graphics backends (graphics.lisp) turn a canvas into bytes for a specific
;; terminal, and the TUI (tui.lisp) turns it into text lines.
;;
;; Canvas representation (alist):
;;   (:width . W) (:height . H)        ; logical units, origin at centre
;;   (:segments . SEGMENTS)             ; list of (x1 y1 x2 y2 color)
;;   (:background . COLOR)              ; nil = terminal default
;;
;; Coordinates are Logo coordinates: x right, y up, origin centre.
;; Colors are (r g b) triples of 0..255, or nil for "current/default".
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-canvas)

(defun canvas-make (width height &optional background)
  "Create an empty canvas WIDTH x HEIGHT logical units."
  (list (cons 'width width)
   (cons 'height height)
   (cons 'segments nil)
   (cons 'background background)))

(defun canvas-width (c) (cdr (assoc 'width c)))

(defun canvas-height (c) (cdr (assoc 'height c)))

(defun canvas-segments (c) (cdr (assoc 'segments c)))

(defun canvas-background (c) (cdr (assoc 'background c)))

(defun canvas-add-segment (c x1 y1 x2 y2 color)
  "Return a new canvas with segment (X1,Y1)-(X2,Y2) appended."
  (let* ((seg (list x1 y1 x2 y2 color)))
    (list (cons 'width (canvas-width c))
     (cons 'height (canvas-height c))
     (cons 'segments (append (canvas-segments c) (list seg)))
     (cons 'background (canvas-background c)))))

(defun canvas-clear (c)
  "Return an empty canvas with the same size and background."
  (canvas-make (canvas-width c) (canvas-height c) (canvas-background c)))

(defun canvas-bounds (c)
  "Return (minx miny maxx maxy) over all segment endpoints, or nil if empty."
  (let* ((segs (canvas-segments c)))
    (if (null? segs)
      nil
      (let loop ((rest segs)
                 (minx (car (car segs)))
                 (miny (cadr (car segs)))
                 (maxx (car (car segs)))
                 (maxy (cadr (car segs))))
        (if (null? rest)
          (list minx miny maxx maxy)
          (let* ((s (car rest))
                 (x1 (car s))
                 (y1 (cadr s))
                 (x2 (car (cddr s)))
                 (y2 (cadr (cddr s))))
            (loop (cdr rest)
             (if (< x1 minx) x1 minx)
             (if (< y1 miny) y1 miny)
             (if (> x2 maxx) x2 maxx)
             (if (> y2 maxy) y2 maxy))))))))

;; ---------------------------------------------------------------------------
;; Rasterization: Bresenham line on an integer dot grid
;; ---------------------------------------------------------------------------
(defun canvas-rasterize (c cols rows)
  "Rasterize canvas C into a grid of COLS x ROWS dots (0/1).
   Returns a vector of ROWS vectors, each of COLS integers (0 or 1).
   Row 0 is the TOP of the picture (y-up Logo coords flipped).
   The canvas is scaled to fit, preserving aspect, centred."
  (let* ((w (canvas-width c))
         (h (canvas-height c))
         (grid (make-vector rows 0)))
    (do ((r 0 (+ r 1))) ((>= r rows))
      (vector-set! grid r (make-vector cols 0)))
    (let* ((scale (min (/ (- cols 1) (max w 1)) (/ (- rows 1) (max h 1)))))
      (let loop ((segs (canvas-segments c)))
        (if (null? segs)
          grid
          (let* ((s (car segs))
                 (x1 (floor (+ (* (car s) scale) (/ (- cols 1) 2))))
                 (y1 (floor (+ (* (cadr s) scale) (/ (- rows 1) 2))))
                 (x2 (floor (+ (* (car (cddr s)) scale) (/ (- cols 1) 2))))
                 (y2 (floor (+ (* (cadr (cddr s)) scale) (/ (- rows 1) 2)))))
            (canvas-plot-line grid cols rows x1 y1 x2 y2)
            (loop (cdr segs))))))))

(defun canvas-plot-line (grid cols rows x1 y1 x2 y2)
  "Plot a Bresenham line into GRID. Mutates the row vectors."
  (let* ((dx (abs (- x2 x1)))
         (dy (abs (- y2 y1)))
         (sx (if (< x1 x2) 1 -1))
         (sy (if (< y1 y2) 1 -1))
         (err (- dx dy)))
    (let loop ((x x1)
               (y y1)
               (err err))
      (let* ((row (- rows 1 y)))
        (when (and (>= row 0) (< row rows) (>= x 0) (< x cols))
          (vector-set! (vector-ref grid row) x 1)))
      (if (and (= x x2) (= y y2))
        grid
        ;; Classic Bresenham (err = dx - dy, dy positive): err accumulates
        ;; -dy on x-steps and +dx on y-steps. Both branches may fire
        ;; (a diagonal step); e2 == -dy / e2 == dx must step, hence >=/<=.
        (let* ((e2 (* 2 err))
               (err2 (if (>= e2 (- dy)) (- err dy) err))
               (nx (if (>= e2 (- dy)) (+ x sx) x))
               (err3 (if (<= e2 dx) (+ err2 dx) err2))
               (ny (if (<= e2 dx) (+ y sy) y)))
          (loop nx ny err3))))))

;; ---------------------------------------------------------------------------
;; Braille rendering: 2x4 dots per character cell (U+2800 block)
;; ---------------------------------------------------------------------------

;; Braille dot layout within a cell (col, row), origin top-left:
;;   (0,0)=bit0 (0,1)=bit1 (0,2)=bit2 (1,0)=bit3 (1,1)=bit4 (1,2)=bit5
;;   (0,3)=bit6 (1,3)=bit7
(define *braille-bits*
  (list (list 0 0 1) (list 0 1 2) (list 0 2 4) (list 1 0 8)
   (list 1 1 16) (list 1 2 32) (list 0 3 64) (list 1 3 128)))

(defun canvas->braille-lines (c cols rows)
  "Render canvas C as a list of ROWS strings, each of COLS Braille
   characters (2x4 dots per cell, so COLS*2 x ROWS*4 dots of resolution)."
  (let* ((grid (canvas-rasterize c (* cols 2) (* rows 4)))
         (lines nil))
    (do ((r 0 (+ r 1))) ((>= r rows) (reverse lines))
      (let* ((line ""))
        (do ((col 0 (+ col 1))) ((>= col cols))
          (let* ((bits 0))
            (let loop ((dots *braille-bits*))
              (if (null? dots)
                nil
                (let* ((d (car dots)))
                  (when
                    (=
                     (vector-ref (vector-ref grid (+ (* r 4) (cadr d)))
                      (+ (* col 2) (car d))) 1)
                    (set! bits (+ bits (caddr d))))
                  (loop (cdr dots)))))
            (set! line (concat line (char->string (code-char (+ #x2800 bits)))))))
        (set! lines (cons line lines))))))
