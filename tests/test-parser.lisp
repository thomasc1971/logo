;; test-parser.lisp - Tests for the Logo tokenizer and parser
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

;; Tokenizer
(assert-equal '((:word "FD") (:num 100))
 (logo-tokenize "FD 100") "tokenize FD 100")
(assert-equal '((:word "FD") (:num -50))
 (logo-tokenize "FD -50") "tokenize negative number")
(assert-equal '((:word "PRINT") (:string "hello world"))
 (logo-tokenize "PRINT \"hello world\"") "tokenize string")
(assert-equal '((:word "FD") (:var "X"))
 (logo-tokenize "FD :x") "tokenize variable (upcased)")
(assert-equal '((:word "FD") (:num 10))
 (logo-tokenize "FD 10 \\ comment\n") "tokenize comment")
(assert-equal '((:word "FD") (:num 10))
 (logo-tokenize "fd 10") "tokenizer uppercases words")
(assert-equal '((:word "BLÅ")) (logo-tokenize "blå")
 "tokenizer uppercases the Danish letters")
(assert-equal '((:word "FD") (:var "MÅL")) (logo-tokenize "FD :mål")
 "tokenizer uppercases Danish variable names")

;; Parser: flat command stream split by arity
(assert-equal '((cmd "FD" 100) (cmd "RT" 90))
 (logo-parse "FD 100 RT 90") "parse two commands")
(assert-equal '((cmd "FD" 100) (cmd "CS"))
 (logo-parse "FD 100 CS") "parse zero-arity command")

;; Parser: REPEAT with bracket body
(assert-equal '((repeat 4 ((cmd "FD" 50) (cmd "RT" 90))))
 (logo-parse "REPEAT 4 [FD 50 RT 90]") "parse REPEAT")

;; Parser: TO ... END with parameters
(assert-equal
 '((to "SQUARE" ("S") ((cmd "FD" (:var "S"))))
   (cmd "SQUARE" 80))
 (logo-parse "TO SQUARE :S FD :S END SQUARE 80")
 "parse TO with param")

;; Parser: nested brackets and IF (PENDOWNP is a 0-arity value primitive)
(assert-equal '((if (:call "PENDOWNP" nil) ((cmd "FD" 1))))
 (logo-parse "IF PENDOWNP [FD 1]") "parse IF (bracket body)")
(assert-equal '((repeat 2 ((repeat 3 ((cmd "FD" 1))))))
 (logo-parse "REPEAT 2 [REPEAT 3 [FD 1]]") "parse nested REPEAT")

;; Parser: case-insensitivity
(assert-equal '((cmd "FD" 10))
 (logo-parse "fd 10") "parse lowercase")

;; Parser: value primitive as argument (FD XCOR is not valid, but
;; PRINT SUM [1 2] is: SUM is a 1-arity value primitive taking a list)
(assert-equal '((cmd "PRINT" (:call "SUM" ((:list (1 2))))))
 (logo-parse "PRINT SUM [1 2]") "parse value-primitive call")

;; Parser: unknown word is an error. Errors arrive as error values via
;; logo-run (Ditty condition-case substitutes and resumes, so a bare
;; condition-case around logo-parse cannot reliably detect them).
(assert-equal #t (error? (logo-run "WIBBLE 3")) "unknown word errors")

;; Parser: truncated special forms are errors, not crashes/secondary errors.
;; Each sub-form result must be error?-checked before destructuring.
(defun assert-parse-error (source description)
  (assert-equal #t (error? (logo-run source)) description))

(assert-parse-error "OUTPUT" "OUTPUT without argument errors")
(assert-parse-error "IF" "IF without condition errors")
(assert-parse-error "IF 1" "IF without bracket body errors")
(assert-parse-error "IFELSE 1 [FD 1]" "IFELSE without else body errors")
(assert-parse-error "REPEAT" "REPEAT without count errors")
(assert-parse-error "MAKE :X" "MAKE without value errors")
(assert-parse-error "RUN" "RUN without bracket body errors")
(assert-parse-error "THING" "THING without name errors")
(assert-parse-error "TO" "TO without name errors")
(assert-parse-error "TO FOO" "TO without END errors")
(assert-parse-error "REPEAT 2 [FD 10" "unterminated bracket errors")

(format #t "~%Passed: ~a, Failed: ~a~%" passed failed)

(if (> failed 0) (exit 1) (exit 0))
