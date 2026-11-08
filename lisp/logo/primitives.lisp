;; primitives.lisp - Logo primitive registry
;;
;; Two tables, both keyed by UPPERCASED name:
;;
;;   *logo-primitives*       name -> (ARITY . FN)
;;                           FN: (turtle args) -> turtle'
;;                           (commands: FD, RT, CS, PRINT, ...)
;;   *logo-value-primitives* name -> (ARITY . FN)
;;                           FN: (turtle args) -> value
;;                           (queries: XCOR, SUM, RANDOM, ...)
;;
;; Special forms (MAKE, IF, REPEAT, RUN, TO, OUTPUT, ...) are NOT here:
;; they need unevaluated instruction lists, so the interpreter dispatches
;; them before argument evaluation. See interpreter.lisp.
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-primitives)

(define *logo-primitives* (make-hash-table))

(define *logo-value-primitives* (make-hash-table))

(defun logo-define-primitive (name arity fn)
  "Register command NAME with ARITY args; FN is (turtle args) -> turtle'."
  (hash-set! *logo-primitives* name (cons arity fn)))

(defun logo-define-value-primitive (name arity fn)
  "Register query NAME with ARITY args; FN is (turtle args) -> value."
  (hash-set! *logo-value-primitives* name (cons arity fn)))

(defun logo-primitive-arity (name)
  "Return the arity of primitive NAME, or nil if NAME is not a primitive."
  (let* ((entry (hash-ref *logo-primitives* name)))
    (if entry
      (car entry)
      (let* ((ventry (hash-ref *logo-value-primitives* name)))
        (if ventry (car ventry) nil)))))

;; ---------------------------------------------------------------------------
;; Turtle commands
;; ---------------------------------------------------------------------------
(logo-define-primitive "FD" 1 (lambda (t args) (turtle-forward t (car args))))
(logo-define-primitive "FORWARD" 1
 (lambda (t args) (turtle-forward t (car args))))
(logo-define-primitive "BK" 1
 (lambda (t args) (turtle-forward t (- 0 (car args)))))
(logo-define-primitive "BACK" 1
 (lambda (t args) (turtle-forward t (- 0 (car args)))))
(logo-define-primitive "RT" 1 (lambda (t args) (turtle-turn t (car args))))
(logo-define-primitive "RIGHT" 1 (lambda (t args) (turtle-turn t (car args))))
(logo-define-primitive "LT" 1
 (lambda (t args) (turtle-turn t (- 0 (car args)))))
(logo-define-primitive "LEFT" 1
 (lambda (t args) (turtle-turn t (- 0 (car args)))))
(logo-define-primitive "SETH" 1
 (lambda (t args) (turtle-set-heading t (car args))))
(logo-define-primitive "SETHEADING" 1
 (lambda (t args) (turtle-set-heading t (car args))))
(logo-define-primitive "SETX" 1
 (lambda (t args) (turtle-move-to t (car args) (turtle-y t))))
(logo-define-primitive "SETY" 1
 (lambda (t args) (turtle-move-to t (turtle-x t) (car args))))
(logo-define-primitive "HOME" 0 (lambda (t args) (turtle-home t)))
(logo-define-primitive "CS" 0 (lambda (t args) (turtle-clear t)))
(logo-define-primitive "CLEAN" 0 (lambda (t args) (turtle-clear t)))
(logo-define-primitive "PU" 0 (lambda (t args) (turtle-with t 'pen-down #f)))
(logo-define-primitive "PENUP" 0 (lambda (t args) (turtle-with t 'pen-down #f)))
(logo-define-primitive "PD" 0 (lambda (t args) (turtle-with t 'pen-down #t)))
(logo-define-primitive "PENDOWN" 0
 (lambda (t args) (turtle-with t 'pen-down #t)))
(logo-define-primitive "ST" 0 (lambda (t args) (turtle-with t 'visible #t)))
(logo-define-primitive "SHOWTURTLE" 0
 (lambda (t args) (turtle-with t 'visible #t)))
(logo-define-primitive "HT" 0 (lambda (t args) (turtle-with t 'visible #f)))
(logo-define-primitive "HIDETURTLE" 0
 (lambda (t args) (turtle-with t 'visible #f)))

(defun logo-set-pen-color (t color)
  "Set pen color. COLOR is a (r g b) list, a number (palette index), or a
   color-name string. Mirrors UCBLogo SETPC loosely; v1 keeps the list form."
  (turtle-with t 'pen-color
   (if (list? color)
     color
     (if (number? color) (list color color color) nil))))

(logo-define-primitive "SETPC" 1
 (lambda (t args) (logo-set-pen-color t (car args))))
(logo-define-primitive "SETPENCOLOR" 1
 (lambda (t args) (logo-set-pen-color t (car args))))
(logo-define-primitive "SETBG" 1
 (lambda (t args)
   (turtle-with t 'canvas
    (canvas-make (canvas-width (turtle-canvas t))
     (canvas-height (turtle-canvas t))
     (car args)))))

;; PRINT / PR / SHOW echo to the transcript (the headless equivalent of the
;; RC759's output area). PRINT takes exactly one argument in this dialect.
(logo-define-primitive "PRINT" 1 (lambda (t args) (turtle-print t (car args))))
(logo-define-primitive "PR" 1 (lambda (t args) (turtle-print t (car args))))
(logo-define-primitive "SHOW" 1 (lambda (t args) (turtle-print t (car args))))

;; ---------------------------------------------------------------------------
;; Value primitives (queries and arithmetic)
;; ---------------------------------------------------------------------------
(logo-define-value-primitive "XCOR" 0 (lambda (t args) (turtle-x t)))
(logo-define-value-primitive "YCOR" 0 (lambda (t args) (turtle-y t)))
(logo-define-value-primitive "HEADING" 0 (lambda (t args) (turtle-heading t)))
(logo-define-value-primitive "PENDOWNP" 0
 (lambda (t args) (if (turtle-pen-down? t) #t #f)))

(defun logo-number-list (xs)
  "Coerce XS to a list of numbers (a bare number becomes a 1-list)."
  (if (list? xs) xs (list xs)))

(logo-define-value-primitive "SUM" 1
 (lambda (t args)
   (let loop ((nums (logo-number-list (car args)))
              (acc 0))
     (if (null? nums) acc (loop (cdr nums) (+ acc (car nums)))))))
(logo-define-value-primitive "PRODUCT" 1
 (lambda (t args)
   (let loop ((nums (logo-number-list (car args)))
              (acc 1))
     (if (null? nums) acc (loop (cdr nums) (* acc (car nums)))))))
(logo-define-value-primitive "DIFFERENCE" 2
 (lambda (t args) (- (car args) (cadr args))))
(logo-define-value-primitive "QUOTIENT" 2
 (lambda (t args) (/ (car args) (cadr args))))
(logo-define-value-primitive "REMAINDER" 2
 (lambda (t args)
   (let* ((a (car args))
          (b (cadr args)))
     (- a (* b (logo-real-floor (/ a b)))))))
(logo-define-value-primitive "ABS" 1 (lambda (t args) (logo-abs (car args))))
(logo-define-value-primitive "RANDOM" 1
 (lambda (t args)
   (let* ((n (car args)))
     (if (<= n 0)
       0
       (floor (* (logo-random) n) 1)))))
(logo-define-value-primitive "GREATER?" 2
 (lambda (t args) (if (> (car args) (cadr args)) #t #f)))
(logo-define-value-primitive "LESS?" 2
 (lambda (t args) (if (< (car args) (cadr args)) #t #f)))
(logo-define-value-primitive "EQUAL?" 2
 (lambda (t args) (if (equal? (car args) (cadr args)) #t #f)))
(logo-define-value-primitive "COUNT" 1
 (lambda (t args) (if (list? (car args)) (length (car args)) 1)))
(logo-define-value-primitive "FIRST" 1
 (lambda (t args) (if (list? (car args)) (car (car args)) (car args))))
(logo-define-value-primitive "LAST" 1
 (lambda (t args)
   (let loop ((xs (car args)))
     (if (null? (cdr xs)) (car xs) (loop (cdr xs))))))
(logo-define-value-primitive "BUTLAST" 1
 (lambda (t args)
   (let loop ((xs (car args))
              (acc nil))
     (if (null? (cdr xs))
       (reverse acc)
       (loop (cdr xs) (cons (car xs) acc))))))
