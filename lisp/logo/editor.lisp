;; editor.lisp - Headless 21-line Mikro-Logo procedure editor buffer
;;
;; The RC759 editor is a fixed page: the header, at most 19 statement lines
;; and SLUT (manual 4.4.4, 5.1.1). This module owns the buffer, cursor and
;; line editing semantics; it has no Tapestry or terminal dependencies so it
;; runs headlessly in tests. tui.lisp maps terminal keys to these operations.
;;
;; Editor state is an alist:
;;   lines   exactly 21 strings
;;   row     cursor row, 0..20
;;   col     cursor column, 0..line length (length = trailing blank)
;;   top     first visible row
;;   left    first visible column
;;   name    procedure name being edited, or nil
;;   origin  'learn or 'ret
;;   error   local status message, or nil
;;
;; Internal file: loaded by logo.lisp into the `logo` package.
(provide 'logo-editor)

(define *logo-editor-lines* 21)

(define *logo-editor-indent* 3)

(defun logo-editor-blank-lines (n)
  "Return a list of N empty strings."
  (let loop ((n n)
             (out nil))
    (if (<= n 0)
      out
      (loop (- n 1) (cons "" out)))))

(defun logo-editor-pad-lines (lines)
  "Pad or truncate LINES to exactly 21 entries."
  (let loop ((rest lines)
             (n 0)
             (out nil))
    (if (= n *logo-editor-lines*)
      (reverse out)
      (if (null? rest)
        (loop nil (+ n 1) (cons "" out))
        (loop (cdr rest) (+ n 1) (cons (car rest) out))))))

(defun logo-editor-with (editor key value)
  "Return EDITOR with KEY set to VALUE."
  (let* ((bindings nil))
    (let loop ((rest editor))
      (if (null? rest)
        nil
        (let* ((b (car rest)))
          (when (not (eq? (car b) key)) (set! bindings (cons b bindings)))
          (loop (cdr rest)))))
    (cons (cons key value) (reverse bindings))))

(defun logo-editor-make (lines name origin)
  "Create an editor buffer from LINES, NAME and ORIGIN."
  (let* ((padded (logo-editor-pad-lines lines))
         (row (if (eq? origin 'learn) 0 0))
         (col (if (eq? origin 'learn) (length (car padded)) 0)))
    (list (cons 'lines padded)
     (cons 'row row)
     (cons 'col col)
     (cons 'top 0)
     (cons 'left 0)
     (cons 'name name)
     (cons 'origin origin)
     (cons 'error nil))))

(defun logo-editor-learn ()
  "A fresh LÆR page: BEGYND on the first line, twenty blank lines."
  (logo-editor-make
   (cons "begynd " (logo-editor-blank-lines (- *logo-editor-lines* 1)))
   nil 'learn))

(defun logo-editor-ret (lines name)
  "An editor page loaded with LINES for procedure NAME."
  (logo-editor-make lines name 'ret))

(defun logo-editor-lines (e) (cdr (assoc 'lines e)))

(defun logo-editor-row (e) (cdr (assoc 'row e)))

(defun logo-editor-col (e) (cdr (assoc 'col e)))

(defun logo-editor-top (e) (cdr (assoc 'top e)))

(defun logo-editor-left (e) (cdr (assoc 'left e)))

(defun logo-editor-name (e) (cdr (assoc 'name e)))

(defun logo-editor-origin (e) (cdr (assoc 'origin e)))

(defun logo-editor-error (e) (cdr (assoc 'error e)))

(defun logo-editor-line (e row)
  (list-ref (logo-editor-lines e) row))

(defun logo-editor-current-line (e)
  (logo-editor-line e (logo-editor-row e)))

(defun logo-editor-replace-line (lines row value)
  "Return LINES with ROW replaced by VALUE."
  (let loop ((rest lines)
             (n 0)
             (out nil))
    (if (null? rest)
      (reverse out)
      (loop (cdr rest) (+ n 1)
       (cons (if (= n row) value (car rest)) out)))))

(defun logo-editor-set-line (e value)
  (let* ((e2 (logo-editor-with e 'error nil)))
    (logo-editor-with e2 'lines
     (logo-editor-replace-line (logo-editor-lines e2) (logo-editor-row e2)
      value))))

(defun logo-editor-set-cursor (e row col)
  (let* ((e2 (logo-editor-with e 'error nil)))
    (logo-editor-with (logo-editor-with e2 'row row) 'col col)))

(defun logo-editor-clamp-col (e row col)
  (min col (length (logo-editor-line e row))))

(defun logo-editor-move-left (e)
  "Move left; at column zero, go to the previous line's last character."
  (let* ((row (logo-editor-row e))
         (col (logo-editor-col e)))
    (cond
      ((> col 0) (logo-editor-set-cursor e row (- col 1)))
      ((> row 0)
       (let* ((prev (- row 1))
              (len (length (logo-editor-line e prev))))
         (logo-editor-set-cursor e prev (if (> len 0) (- len 1) 0))))
      (#t e))))

(defun logo-editor-move-right (e)
  "Move right; from the last character, go to the next line's first character."
  (let* ((row (logo-editor-row e))
         (col (logo-editor-col e))
         (len (length (logo-editor-current-line e))))
    (cond
      ((< row (- *logo-editor-lines* 1))
       (if (or (= len 0) (>= col (- len 1)))
         (logo-editor-set-cursor e (+ row 1) 0)
         (logo-editor-set-cursor e row (+ col 1))))
      ((< col len) (logo-editor-set-cursor e row (+ col 1)))
      (#t e))))

(defun logo-editor-move-up (e)
  (let* ((row (logo-editor-row e)))
    (if (<= row 0)
      e
      (let* ((row2 (- row 1)))
        (logo-editor-set-cursor e row2
         (logo-editor-clamp-col e row2 (logo-editor-col e)))))))

(defun logo-editor-move-down (e)
  (let* ((row (logo-editor-row e)))
    (if (>= row (- *logo-editor-lines* 1))
      e
      (let* ((row2 (+ row 1)))
        (logo-editor-set-cursor e row2
         (logo-editor-clamp-col e row2 (logo-editor-col e)))))))

(defun logo-editor-home (e)
  (logo-editor-set-cursor e (logo-editor-row e) 0))

(defun logo-editor-end (e)
  (logo-editor-set-cursor e (logo-editor-row e)
   (length (logo-editor-current-line e))))

(defun logo-editor-insert-text (e text)
  "Insert TEXT at the cursor."
  (let* ((line (logo-editor-current-line e))
         (col (min (logo-editor-col e) (length line)))
         (new
          (concat (substring line 0 col) text
           (substring line col
            (length line)))))
    (logo-editor-set-cursor (logo-editor-set-line e new)
     (logo-editor-row e) (+ col (length text)))))

(defun logo-editor-insert-space (e)
  (logo-editor-insert-text e " "))

(defun logo-editor-join-with-next (e)
  "Join the current line and the next line, removing the next line."
  (let* ((row (logo-editor-row e))
         (lines (logo-editor-lines e))
         (here (list-ref lines row))
         (next (list-ref lines (+ row 1)))
         (joined (concat here next))
         (shifted
          (let loop ((i 0)
                     (out nil))
            (if (= i *logo-editor-lines*)
              (reverse out)
              (loop (+ i 1)
               (cons
                (cond
                  ((= i row) joined)
                  ((> i row)
                   (if (= i (- *logo-editor-lines* 1))
                     ""
                     (list-ref lines (+ i 1))))
                  (#t (list-ref lines i)))
                out)))))
         (e2 (logo-editor-with e 'lines shifted)))
    (logo-editor-set-cursor e2 row (length here))))

(defun logo-editor-delete (e)
  "Delete the character under the cursor, or join the next line at end."
  (let* ((line (logo-editor-current-line e))
         (col (logo-editor-col e))
         (len (length line))
         (row (logo-editor-row e)))
    (cond
      ((< col len)
       (let* ((new
               (concat (substring line 0 col) (substring line (+ col 1) len))))
         (logo-editor-set-line e new)))
      ((< row (- *logo-editor-lines* 1)) (logo-editor-join-with-next e))
      (#t e))))

(defun logo-editor-backspace (e)
  "Delete the character left of the cursor, joining lines at column zero."
  (let* ((row (logo-editor-row e))
         (col (logo-editor-col e))
         (line (logo-editor-current-line e)))
    (cond
      ((> col 0)
       (let* ((new
               (concat (substring line 0 (- col 1))
                (substring line col (length line)))))
         (logo-editor-set-cursor (logo-editor-set-line e new) row (- col 1))))
      ((> row 0)
       (let* ((prev-row (- row 1))
              (prev (logo-editor-line e prev-row))
              (joined (concat prev line))
              (lines (logo-editor-lines e))
              (shifted
               (let loop ((i 0)
                          (out nil))
                 (if (= i *logo-editor-lines*)
                   (reverse out)
                   (loop (+ i 1)
                    (cons
                     (cond
                       ((= i prev-row) joined)
                       ((>= i row)
                        (if (= i (- *logo-editor-lines* 1))
                          ""
                          (list-ref lines (+ i 1))))
                       (#t (list-ref lines i)))
                     out))))))
         (logo-editor-set-cursor (logo-editor-with e 'lines shifted)
          prev-row (length prev))))
      (#t e))))

(defun logo-editor-kill-to-end (e)
  "Delete from the cursor to the end of the current line."
  (let* ((line (logo-editor-current-line e))
         (col (min (logo-editor-col e) (length line))))
    (logo-editor-set-line e (substring line 0 col))))

(defun logo-editor-delete-line (e)
  "Delete the current line, shifting following lines up."
  (let* ((row (logo-editor-row e))
         (lines (logo-editor-lines e))
         (shifted
          (let loop ((i 0)
                     (out nil))
            (if (= i *logo-editor-lines*)
              (reverse out)
              (loop (+ i 1)
               (cons
                (cond
                  ((< i row) (list-ref lines i))
                  ((= i (- *logo-editor-lines* 1)) "")
                  (#t (list-ref lines (+ i 1))))
                out))))))
    (logo-editor-set-cursor (logo-editor-with e 'lines shifted) row 0)))

(defun logo-editor-insert-line (e)
  "Insert a blank line at the cursor if the last page line is blank."
  (let* ((row (logo-editor-row e))
         (lines (logo-editor-lines e)))
    (if (not (equal? (list-ref lines (- *logo-editor-lines* 1)) ""))
      (logo-editor-with e 'error "For mange linier")
      (let* ((shifted
              (let loop ((i 0)
                         (out nil))
                (if (= i *logo-editor-lines*)
                  (reverse out)
                  (loop (+ i 1)
                   (cons
                    (cond
                      ((< i row) (list-ref lines i))
                      ((= i row) "")
                      (#t (list-ref lines (- i 1))))
                    out))))))
        (logo-editor-set-cursor
         (logo-editor-with (logo-editor-with e 'lines shifted) 'error nil)
         row 0)))))

(defun logo-editor-return (e)
  "Return on the last page line means A4; elsewhere move to the next line."
  (if (>= (logo-editor-row e) (- *logo-editor-lines* 1))
    (cons 'commit e)
    (cons 'update (logo-editor-set-cursor e (+ (logo-editor-row e) 1) 0))))

(defun logo-editor-text (e)
  "Return the editor buffer as one newline-separated string."
  (join (logo-editor-lines e) "\n"))
