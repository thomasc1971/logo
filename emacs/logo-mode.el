;;; logo-mode.el --- Major mode for Logo turtle graphics -*- lexical-binding: t -*-

;; Major mode for Logo source files (.logo), with font-lock for the
;; primitives/special forms. Derives from lisp-mode, like
;; ditty-mode.el does for Ditty Lisp.
;;
;; Installation (development): add this directory to load-path and
;;   (require 'logo-mode)
;;   (add-to-list 'auto-mode-alist '("\\.logo\\'" . logo-mode))

(require 'lisp-mode)

(defgroup logo nil
  "Major mode for Logo turtle graphics."
  :group 'languages)

;; NOTE: this must be a *list of keyword specs* ((REGEXP . FACE)), not a
;; bare regexp string: font-lock-defaults names this variable, and
;; font-lock-compile-keywords errors on a string (symbolp) or on a
;; spec whose face is not in dotted-pair form (listp).
(defconst logo-font-lock-keywords
  (list
   (cons
    (eval-when-compile
      (regexp-opt
       '("FD" "FORWARD" "BK" "BACK" "RT" "RIGHT" "LT" "LEFT"
         "SETH" "SETHEADING" "SETX" "SETY" "HOME" "CS" "CLEAN"
         "PU" "PENUP" "PD" "PENDOWN" "ST" "SHOWTURTLE" "HT" "HIDETURTLE"
         "SETPC" "SETPENCOLOR" "SETBG" "PRINT" "PR" "SHOW"
         "XCOR" "YCOR" "HEADING" "PENDOWNP" "SUM" "PRODUCT" "COUNT"
         "FIRST" "LAST" "BUTLAST" "ABS" "RANDOM" "DIFFERENCE" "QUOTIENT"
         "REMAINDER" "GREATER?" "LESS?" "EQUAL?"
         "TO" "END" "OUTPUT" "STOP" "REPEAT" "IF" "IFELSE" "RUN"
         "MAKE" "THING" "LOCAL")
       'words))
    'font-lock-keyword-face))
  "Font-lock keywords for Logo.")

(defvar logo-mode-syntax-table
  (let ((table (make-syntax-table lisp-mode-syntax-table)))
    (modify-syntax-entry ?\\ "<" table)   ; \ comment to end of line
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    table)
  "Syntax table for `logo-mode'.")

;;;###autoload
(define-derived-mode logo-mode lisp-mode "Logo"
  "Major mode for editing Logo turtle graphics programs."
  :syntax-table logo-mode-syntax-table
  ;; font-lock-defaults: KEYWORDS is a symbol (or list of symbols)
  ;; naming the variable holding the keyword specs.
  (setq-local font-lock-defaults '(logo-font-lock-keywords))
  (setq-local comment-start "\\ "))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.logo\\'" . logo-mode))

(provide 'logo-mode)

;;; logo-mode.el ends here
