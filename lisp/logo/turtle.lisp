;; turtle.lisp - Turtle state and motion
;;
;; The turtle is a pure value (an alist). Every operation returns a NEW
;; turtle state; nothing is mutated. That makes the state trivially
;; serializable for the Tapestry Elm model (tui.lisp) and trivially testable.
;;
;; Turtle state:
;;   (:x . X) (:y . Y)                    ; position, Logo coords (y up)
;;   (:heading . DEG)                    ; 0 = north, clockwise positive
;;   (:pen-down . #t/#f)
;;   (:pen-color . (R G B) or nil)
;;   (:pen-size . N)
;;   (:visible . #t/#f)
;;   (:canvas . CANVAS)                  ; everything drawn so far
;;   (:output . STRINGS)                 ; PRINT/SHOW transcript
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-turtle)

(defun turtle-make (width height)
  "Create a fresh turtle on an empty WIDTH x HEIGHT canvas."
  (list (cons 'x 0.0)
   (cons 'y 0.0)
   (cons 'heading 0)
   (cons 'pen-down #t)
   (cons 'pen-color nil)
   (cons 'pen-size 1)
   (cons 'visible #t)
   (cons 'canvas (canvas-make width height))
   (cons 'output nil)))

(defun turtle-x (t) (cdr (assoc 'x t)))

(defun turtle-y (t) (cdr (assoc 'y t)))

(defun turtle-heading (t) (cdr (assoc 'heading t)))

(defun turtle-pen-down? (t) (cdr (assoc 'pen-down t)))

(defun turtle-pen-color (t) (cdr (assoc 'pen-color t)))

(defun turtle-visible? (t) (cdr (assoc 'visible t)))

(defun turtle-canvas (t) (cdr (assoc 'canvas t)))

(defun turtle-output (t) (cdr (assoc 'output t)))

(defun turtle-with (t key value)
  "Return a copy of turtle T with KEY set to VALUE."
  (let* ((bindings nil))
    (let loop ((rest t))
      (if (null? rest)
        nil
        (let* ((b (car rest)))
          (when (not (eq? (car b) key)) (set! bindings (cons b bindings)))
          (loop (cdr rest)))))
    (cons (cons key value) (reverse bindings))))

(defun turtle-forward (t dist)
  "Move turtle T forward DIST units. Draws a segment if the pen is down."
  (let* ((rad (logo-deg->rad (turtle-heading t)))
         (nx (+ (turtle-x t) (* dist (sin rad))))
         (ny (+ (turtle-y t) (* dist (cos rad)))))
    (turtle-move-to t nx ny)))

(defun turtle-move-to (t nx ny)
  "Move turtle T to (NX, NY), drawing if the pen is down."
  (let* ((t2 (turtle-with (turtle-with t 'x nx) 'y ny)))
    (if (turtle-pen-down? t)
      (turtle-with t2 'canvas
       (canvas-add-segment (turtle-canvas t)
        (turtle-x t) (turtle-y t)
        nx ny (turtle-pen-color t)))
      t2)))

(defun turtle-turn (t degrees)
  "Turn turtle T by DEGREES (clockwise positive, Logo convention)."
  (turtle-with t 'heading
   (logo-normalize-heading (+ (turtle-heading t) degrees))))

(defun turtle-set-heading (t degrees)
  "Set turtle T heading to DEGREES."
  (turtle-with t 'heading (logo-normalize-heading degrees)))

(defun turtle-clear (t)
  "Clear the drawing (CS), keeping position, heading and pen state."
  (turtle-with t 'canvas (canvas-clear (turtle-canvas t))))

(defun turtle-home (t)
  "Move the turtle home (0,0) facing north, drawing if the pen is down."
  (turtle-set-heading (turtle-move-to t 0.0 0.0) 0))

(defun turtle-print (t value)
  "Append VALUE's printed form to the transcript."
  (turtle-with t 'output
   (append (turtle-output t) (list (format nil "~a" value)))))
