;;; line-reminder.el --- Line annotation for changed and saved lines  -*- lexical-binding: t; -*-

;; Copyright (C) 2018-2021  Shen, Jen-Chieh
;; Created date 2018-05-25 15:10:29

;; Author: Shen, Jen-Chieh <jcs090218@gmail.com>
;; Description: Line annotation for changed and saved lines.
;; Keyword: annotation line number linum reminder highlight display
;; Version: 0.5.0
;; Package-Requires: ((emacs "24.4") (indicators "0.0.4") (fringe-helper "1.0.1"))
;; URL: https://github.com/emacs-vs/line-reminder

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Line annotation for changed and saved lines.
;;

;;; Code:

(require 'cl-lib)
(require 'fringe-helper)

(defgroup line-reminder nil
  "Line annotation for changed and saved lines."
  :prefix "line-reminder-"
  :group 'tool
  :link '(url-link :tag "Repository" "https://github.com/emacs-vs/line-reminder"))

(defcustom line-reminder-show-option 'linum
  "Option to show indicators in buffer."
  :group 'line-reminder
  :type '(choice (const :tag "linum" linum)
                 (const :tag "indicators" indicators)))

(defface line-reminder-modified-sign-face
  `((t :foreground "#EFF284"))
  "Modifed sign face."
  :group 'line-reminder)

(defface line-reminder-saved-sign-face
  `((t :foreground "#577430"))
  "Modifed sign face."
  :group 'line-reminder)

(defcustom line-reminder-modified-sign-priority 10
  "Display priority for modified sign."
  :type 'integer
  :group 'line-reminder)

(defcustom line-reminder-saved-sign-priority 1
  "Display priority for saved sign."
  :type 'integer
  :group 'line-reminder)

(defcustom line-reminder-linum-format "%s "
  "Format to display annotation using `linum`."
  :type 'string
  :group 'line-reminder)

(defcustom line-reminder-modified-sign "▐"
  "Modified sign."
  :type 'string
  :group 'line-reminder)

(defcustom line-reminder-saved-sign "▐"
  "Saved sign."
  :type 'string
  :group 'line-reminder)

(defcustom line-reminder-fringe-placed 'left-fringe
  "Line indicators fringe location."
  :type '(choice (const :tag "On the left fringe" left-fringe)
                 (const :tag "On the right fringe" right-fringe))
  :group 'line-reminder)

(fringe-helper-define 'line-reminder--default-bitmap nil
  "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.."
  "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.."
  "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.." "..xxx.."
  "..xxx.." "..xxx..")

(defcustom line-reminder-bitmap 'line-reminder--default-bitmap
  "Line indicators fringe symbol."
  :type 'symbol
  :group 'line-reminder)

(defcustom line-reminder-ignore-buffer-names
  '("[*]Backtrace[*]"
    "[*]Buffer List[*]"
    "[*]Checkdoc Status[*]"
    "[*]Echo Area"
    "[*]helm"
    "[*]Help[*]"
    "magit[-]*[[:ascii:]]*[:]"
    "[*]Minibuf-"
    "[*]Packages[*]"
    "[*]run[*]"
    "[*]shell[*]"
    "[*]undo-tree[*]")
  "Buffer Name list you want to ignore this mode."
  :type 'list
  :group 'line-reminder)

(defcustom line-reminder-disable-commands '()
  "List of commands that wouldn't take effect from this package."
  :type 'list
  :group 'line-reminder)

(defvar-local line-reminder--change-lines '()
  "List of line that change in current temp buffer.")

(defvar-local line-reminder--saved-lines '()
  "List of line that saved in current temp buffer.")

(defvar-local line-reminder--before-max-pt -1
  "Record down the point max for out of range calculation.")

(defvar-local line-reminder--cache-max-line nil
  "Cache prevent counting max line twice.")

(defvar-local line-reminder--before-begin-pt -1
  "Record down the before begin point.")

(defvar-local line-reminder--before-end-pt -1
  "Record down the before end point.")

(defvar-local line-reminder--before-max-linum -1
  "Record down the before maximum line number.")

(defvar-local line-reminder--before-begin-linum -1
  "Record down the before begin line number.")

(defvar-local line-reminder--before-end-linum -1
  "Record down the before end line number.")

(defvar-local line-reminder--undo-cancel-p nil
  "If non-nil, we should remove record of changes/saved lines for undo actions.")

;;
;; (@* "External" )
;;

(defvar linum-format)
(defvar ind-managed-absolute-indicators)
(defvar buffer-undo-tree)
(defvar undo-tree-mode)

(declare-function ind-create-indicator-at-line "ext:indicators.el")
(declare-function ind-clear-indicators-absolute "ext:indicators.el")
(declare-function undo-tree-current "ext:undo-tree.el")
(declare-function undo-tree-node-previous "ext:undo-tree.el")

;;
;; (@* "Util" )
;;

(defun line-reminder--use-indicators-p ()
  "Return non-nil if using indicator, else return nil."
  (equal line-reminder-show-option 'indicators))

(defun line-reminder--line-number-at-pos (&optional pos)
  "Return line number at POS with absolute as default."
  (line-number-at-pos pos t))

(defun line-reminder--contain-list-string-regexp (in-list in-str)
  "Return non-nil if IN-STR is listed in IN-LIST.

This function uses `string-match-p'."
  (cl-some (lambda (elm) (string-match-p elm in-str)) in-list))

(defun line-reminder--contain-list-integer (in-list in-int)
  "Return non-nil if IN-INT is listed in IN-LIST."
  (cl-some (lambda (elm) (= elm in-int)) in-list))

(defun line-reminder--get-priority (face)
  "Return priority by FACE."
  (cl-case face
    (`line-reminder-modified-sign-face line-reminder-modified-sign-priority)
    (`line-reminder-saved-sign-face line-reminder-saved-sign-priority)))

(defun line-reminder--mark-line-by-linum (line face)
  "Mark the LINE by using FACE name."
  (let ((inhibit-message t) (message-log-max nil))
    (ind-create-indicator-at-line
     line :managed t :dynamic t :relative nil :fringe line-reminder-fringe-placed
     :bitmap line-reminder-bitmap :face face
     :priority (line-reminder--get-priority face))))

(defun line-reminder--ind-remove-indicator-at-line (line)
  "Remove the indicator on LINE."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (line-reminder--ind-remove-indicator (point))))

(defun line-reminder--ind-delete-dups ()
  "Remove duplicates for indicators overlay once."
  (when (line-reminder--use-indicators-p)
    (let (record-lst new-lst mkr (mkr-pos -1))
      (dolist (ind ind-managed-absolute-indicators)
        (setq mkr (car ind)
              mkr-pos (marker-position mkr))
        (if (line-reminder--contain-list-integer record-lst mkr-pos)
            (remove-overlays mkr-pos mkr-pos 'ind-indicator-absolute t)
          (push mkr-pos record-lst)
          (push ind new-lst)))
      (setq ind-managed-absolute-indicators new-lst))))

(defun line-reminder--ind-remove-indicator (pos)
  "Remove the indicator to position POS."
  (save-excursion
    (goto-char pos)
    (let ((start-pt (1+ (line-beginning-position))) (end-pt (line-end-position))
          remove-inds)
      (dolist (ind ind-managed-absolute-indicators)
        (let* ((mkr (car ind)) (mkr-pos (marker-position mkr)))
          (when (and (>= mkr-pos start-pt) (<= mkr-pos end-pt))
            (push ind remove-inds))))
      (dolist (ind remove-inds)
        (setq ind-managed-absolute-indicators (remove ind ind-managed-absolute-indicators)))
      (remove-overlays start-pt end-pt 'ind-indicator-absolute t))))

(defun line-reminder--add-line-to-change-line (line)
  "Add LINE to change line list variable."
  (push line line-reminder--change-lines)
  (when (line-reminder--use-indicators-p)
    (line-reminder--mark-line-by-linum line 'line-reminder-modified-sign-face)))

(defun line-reminder--remove-line-from-change-line (line)
  "Remove LINE from all line lists variable."
  (setq line-reminder--change-lines (remove line line-reminder--change-lines)
        line-reminder--saved-lines (remove line line-reminder--saved-lines))
  (when (line-reminder--use-indicators-p)
    (line-reminder--ind-remove-indicator-at-line line)))

(defsubst line-reminder--linum-format-string-align-right ()
  "Return format string align on the right."
  (let ((w (length (number-to-string (count-lines (point-min) (point-max))))))
    (format "%%%dd" w)))

(defsubst line-reminder--get-propertized-normal-sign (line)
  "Return a default propertized normal sign.
LINE : pass in by `linum-format' variable."
  (propertize (format (format line-reminder-linum-format
                              (line-reminder--linum-format-string-align-right))
                      line)
              'face 'linum))

(defsubst line-reminder--get-propertized-modified-sign ()
  "Return a propertized modified sign."
  (propertize line-reminder-modified-sign 'face 'line-reminder-modified-sign-face))

(defsubst line-reminder--get-propertized-saved-sign ()
  "Return a propertized saved sign."
  (propertize line-reminder-saved-sign 'face 'line-reminder-saved-sign-face))

(defun line-reminder--propertized-sign-by-type (type &optional line)
  "Return a propertized sign string by type.
TYPE : type of the propertize sign you want.
LINE : Pass is line number for normal sign."
  (cl-case type
    (normal (if (not line)
                (error "Normal line but with no line number pass in")
              ;; Just return normal linum format.
              (line-reminder--get-propertized-normal-sign line)))
    (modified (line-reminder--get-propertized-modified-sign))
    (saved (line-reminder--get-propertized-saved-sign))))

(defun line-reminder--linum-format (line)
  "Core line reminder format string logic here.
LINE : pass in by `linum-format' variable."
  (let ((reminder-sign "") (result-sign "")
        (normal-sign (line-reminder--propertized-sign-by-type 'normal line))
        is-sign-exists)
    (cond
     ;; NOTE: Check if change lines list.
     ((line-reminder--contain-list-integer line-reminder--change-lines line)
      (setq reminder-sign (line-reminder--propertized-sign-by-type 'modified)
            is-sign-exists t))
     ;; NOTE: Check if saved lines list.
     ((line-reminder--contain-list-integer line-reminder--saved-lines line)
      (setq reminder-sign (line-reminder--propertized-sign-by-type 'saved)
            is-sign-exists t)))

    ;; If the sign exist, then remove the last character from the normal sign.
    ;; So we can keep our the margin/padding the same without modifing the
    ;; margin/padding width.
    (when is-sign-exists
      (setq normal-sign (substring normal-sign 0 (1- (length normal-sign)))))

    ;; Combnie the result format.
    (setq result-sign (concat normal-sign reminder-sign))
    result-sign))

;;
;; (@* "Entry" )
;;

(defun line-reminder--enable ()
  "Enable `line-reminder' in current buffer."
  (cl-case line-reminder-show-option
    (linum
     (require 'linum)
     (setq-local linum-format 'line-reminder--linum-format))
    (indicators
     (require 'indicators)))
  (add-hook 'before-change-functions #'line-reminder--before-change-functions nil t)
  (add-hook 'after-change-functions #'line-reminder--after-change-functions nil t)
  (add-hook 'post-command-hook #'line-reminder--post-command nil t)
  (advice-add 'save-buffer :after #'line-reminder--save-buffer)
  (add-hook 'window-scroll-functions 'line-reminder--start-show-thumb nil t)
  (add-hook 'window-configuration-change-hook 'line-reminder--start-show-thumb nil t))

(defun line-reminder--disable ()
  "Disable `line-reminder' in current buffer."
  (remove-hook 'before-change-functions #'line-reminder--before-change-functions t)
  (remove-hook 'after-change-functions #'line-reminder--after-change-functions t)
  (remove-hook 'post-command-hook #'line-reminder--post-command t)
  (advice-remove 'save-buffer #'line-reminder--save-buffer)
  (line-reminder-clear-reminder-lines-sign)
  (remove-hook 'window-scroll-functions 'line-reminder--start-show-thumb t)
  (remove-hook 'window-configuration-change-hook 'line-reminder--start-show-thumb t))

;;;###autoload
(define-minor-mode line-reminder-mode
  "Minor mode 'line-reminder-mode'."
  :lighter " LR"
  :group line-reminder
  (if line-reminder-mode (line-reminder--enable) (line-reminder--disable)))

(defun line-reminder--turn-on-line-reminder-mode ()
  "Turn on the 'line-reminder-mode'."
  (line-reminder-mode 1))

;;;###autoload
(define-globalized-minor-mode global-line-reminder-mode
  line-reminder-mode line-reminder--turn-on-line-reminder-mode
  :require 'line-reminder)

;;
;; (@* "Core" )
;;

;;;###autoload
(defun line-reminder-clear-reminder-lines-sign ()
  "Clear all the reminder lines' sign."
  (interactive)
  (setq line-reminder--change-lines nil
        line-reminder--saved-lines nil)
  (line-reminder--ind-clear-indicators-absolute)
  (line-reminder--delete-thumb-overlays))

(defun line-reminder--is-valid-line-reminder-situation (&optional beg end)
  "Return non-nil, if the conditions are matched.

Arguments BEG and END are passed in by before/after change functions."
  (and (not buffer-read-only)
       (not (line-reminder--contain-list-string-regexp
             line-reminder-ignore-buffer-names (buffer-name)))
       (not (memq this-command line-reminder-disable-commands))
       (if (and beg end) (and (<= beg (point-max)) (<= end (point-max))) t)))

(defun line-reminder--shift-all-lines-list (in-list start delta)
  "Shift all lines from IN-LIST by from START line with DELTA lines value."
  (let ((index 0))
    (dolist (tmp-linum in-list)
      (when (< start tmp-linum)
        (setf (nth index in-list) (+ tmp-linum delta)))
      (setq index (1+ index))))
  in-list)

(defun line-reminder--shift-all-lines (start delta)
  "Shift all `change` and `saved` lines by from START line with DELTA lines value."
  (setq line-reminder--change-lines
        (line-reminder--shift-all-lines-list line-reminder--change-lines
                                             start
                                             delta))
  (setq line-reminder--saved-lines
        (line-reminder--shift-all-lines-list line-reminder--saved-lines
                                             start
                                             delta)))

(defun line-reminder--remove-lines-out-range ()
  "Remove all the line in the list that are above the last/maxinum line \
or less than zero line in current buffer."
  (let ((last-line-in-buffer line-reminder--cache-max-line)
        (check-lst (append line-reminder--change-lines line-reminder--saved-lines)))
    (dolist (line check-lst)
      ;; If is larger than last/max line in buffer.
      (when (or (< last-line-in-buffer line) (<= line 0))
        ;; Remove line because we are deleting.
        (line-reminder--remove-line-from-change-line line)))))

(defun line-reminder--remove-lines (beg end comm-or-uncomm-p)
  "Remove lines from BEG to END depends on COMM-OR-UNCOMM-P."
  (let ((cur beg))
    ;; Shift one more line when commenting/uncommenting.
    (when comm-or-uncomm-p (setq end (1+ end)))
    (while (< cur end)
      (if comm-or-uncomm-p
          (line-reminder--add-line-to-change-line cur)
        (line-reminder--remove-line-from-change-line cur))
      (setq cur (1+ cur)))))

(defun line-reminder--add-lines (beg end)
  "Add lines from BEG to END."
  (let ((cur beg))
    (while (<= cur end)
      (line-reminder--add-line-to-change-line cur)
      (setq cur (1+ cur)))))

;;;###autoload
(defun line-reminder-transfer-to-saved-lines ()
  "Transfer the `change-lines' to `saved-lines'."
  (interactive)
  (setq line-reminder--saved-lines
        (append line-reminder--saved-lines line-reminder--change-lines))
  ;; Clear the change lines.
  (setq line-reminder--change-lines nil)

  (delete-dups line-reminder--saved-lines)  ; Removed save duplicates
  (line-reminder--remove-lines-out-range)  ; Remove out range.

  (line-reminder--mark-buffer))

(defun line-reminder--ind-clear-indicators-absolute ()
  "Clean up all the indicators."
  (when (line-reminder--use-indicators-p) (ind-clear-indicators-absolute)))

(defun line-reminder--mark-buffer ()
  "Mark the whole buffer."
  (when (line-reminder--use-indicators-p)
    (save-excursion
      (line-reminder--ind-clear-indicators-absolute)
      (dolist (line line-reminder--change-lines)
        (line-reminder--mark-line-by-linum line 'line-reminder-modified-sign-face))
      (dolist (line line-reminder--saved-lines)
        (line-reminder--mark-line-by-linum line 'line-reminder-saved-sign-face))
      (line-reminder--start-show-thumb))))

(defun line-reminder--before-change-functions (beg end)
  "Do stuff before buffer is changed with BEG and END."
  (when (line-reminder--is-valid-line-reminder-situation beg end)
    ;; If buffer consider virtual buffer like `*scratch*`, then always
    ;; treat it as modified
    (setq line-reminder--undo-cancel-p (and (buffer-file-name) undo-in-progress))
    (line-reminder--ind-delete-dups)
    (setq line-reminder--before-max-pt (point-max)
          line-reminder--before-max-linum (line-reminder--line-number-at-pos (point-max)))
    (setq line-reminder--before-begin-pt beg
          line-reminder--before-begin-linum (line-reminder--line-number-at-pos beg))
    (setq line-reminder--before-end-pt end
          line-reminder--before-end-linum (line-reminder--line-number-at-pos end))))

(defun line-reminder--after-change-functions (beg end len)
  "Do stuff after buffer is changed with BEG, END and LEN."
  (when (line-reminder--is-valid-line-reminder-situation beg end)
    (save-excursion
      ;; When begin and end are not the same, meaning the there is addition/deletion
      ;; happening in the current buffer.
      (let ((begin-linum -1) (end-linum -1) (delta-lines 0)
            (starting-line -1)  ; Starting line for shift
            (adding-p (< (+ beg len) end))
            ;; Flag to check if currently commenting or uncommenting.
            (comm-or-uncomm-p (and (not (= len 0)) (not (= beg end)))))
        (if (or adding-p comm-or-uncomm-p)
            (setq line-reminder--before-max-pt (+ line-reminder--before-max-pt (- end beg)))
          (setq line-reminder--before-max-pt (- line-reminder--before-max-pt len)))

        (setq line-reminder--cache-max-line
              (line-reminder--line-number-at-pos line-reminder--before-max-pt))

        (if adding-p
            (setq end-linum (line-reminder--line-number-at-pos end)
                  begin-linum (line-reminder--line-number-at-pos beg))
          (setq beg line-reminder--before-begin-pt
                end line-reminder--before-end-pt
                begin-linum line-reminder--before-begin-linum
                end-linum line-reminder--before-end-linum))

        (goto-char beg)

        (if comm-or-uncomm-p
            (setq delta-lines (- line-reminder--cache-max-line line-reminder--before-max-linum))
          (setq delta-lines (- end-linum begin-linum))
          (unless adding-p (setq delta-lines (- 0 delta-lines))))

        ;; Just add the current line.
        (line-reminder--add-line-to-change-line begin-linum)

        ;; If adding line, bound is the begin line number.
        (setq starting-line begin-linum)

        ;; NOTE: Deletion..
        (unless adding-p
          (line-reminder--remove-lines begin-linum end-linum comm-or-uncomm-p)
          (line-reminder--shift-all-lines starting-line delta-lines))

        ;; Just add the current line.
        (line-reminder--add-line-to-change-line begin-linum)

        ;; NOTE: Addition..
        (when adding-p
          (line-reminder--shift-all-lines starting-line delta-lines)
          (line-reminder--add-lines begin-linum end-linum))

        (delete-dups line-reminder--change-lines)
        (delete-dups line-reminder--saved-lines)

        ;; Remove out range.
        (line-reminder--remove-lines-out-range)))))

;;
;; (@* "Save" )
;;

(defun line-reminder--save-buffer (&rest _)
  "Advice execute after function `save-buffer'."
  (when line-reminder-mode (line-reminder-transfer-to-saved-lines)))

;;
;; (@* "Undo" )
;;

(defun line-reminder--undo-tree-root-p ()
  "Return non-nil, if undo is at the root of the undo list."
  (or (eq buffer-undo-list t)
      (null (undo-tree-node-previous (undo-tree-current buffer-undo-tree)))))

(defun line-reminder--undo-root-p ()
  "Compatible version to check root of undo list for different undo packages."
  (cond
   ((and (featurep 'undo-tree) undo-tree-mode)
    (ignore-errors (line-reminder--undo-tree-root-p)))
   (t (eq pending-undo-list t))))

(defun line-reminder--post-command ()
  "Post command for undo cancelling."
  (when (and line-reminder--undo-cancel-p (line-reminder--undo-root-p))
    (setq line-reminder--change-lines nil
          line-reminder--saved-lines nil)
    (line-reminder--ind-clear-indicators-absolute)))

;;
;; (@* "Minimap" )
;;

(defcustom line-reminder-thumbnail nil
  "Show thumbnail in the opposite fringe from `line-reminder-fringe-placed'."
  :type 'boolean
  :group 'line-reminder)

(defcustom line-reminder-thumbnail-delay 0.2
  "Delay time to display thumbnail."
  :type 'float
  :group 'line-reminder)

(fringe-helper-define 'line-reminder--default-thumbnail-bitmap nil
  "xxx...." "xxx...." "xxx...." "xxx...." "xxx...." "xxx...." "xxx...."
  "xxx...." "xxx...." "xxx...." "xxx...." "xxx...." "xxx...." "xxx...."
  "xxx...." "xxx...." "xxx...." "xxx...." "xxx...." "xxx...." "xxx...."
  "xxx...." "xxx....")

(defcustom line-reminder-thumbnail-bitmap 'line-reminder--default-thumbnail-bitmap
  "Bitmap for thumbnail."
  :type 'symbol
  :group 'line-reminder)

(defvar-local line-reminder--thumbnail-overlays nil
  "Overlays indicate thumbnail.")

(defun line-reminder--oppose-fringe (fringe)
  "Return opposite FRINGE type."
  (cl-case fringe
    (`left-fringe 'right-fringe)
    (`right-fringe 'left-fringe)))

(defun line-reminder--window-height ()
  "`line-spacing'-aware calculation of `window-height'."
  (if (and (fboundp 'window-pixel-height)
           (fboundp 'line-pixel-height)
           (display-graphic-p))
      (/ (window-pixel-height) (line-pixel-height))
    (window-height)))

(defun line-reminder--create-thumb-overlay (face)
  "Create single thumbnail overlay with FACE."
  (let* ((left-or-right (line-reminder--oppose-fringe line-reminder-fringe-placed))
         (pos (point))
         ;; If `pos' is at the beginning of line, overlay of the
         ;; fringe will be on the previous visual line.
         (pos (if (= (line-end-position) pos) pos (1+ pos)))
         (display-string `(,left-or-right ,line-reminder-thumbnail-bitmap ,face))
         (after-string (propertize "." 'display display-string))
         (overlay (make-overlay pos pos)))
    (overlay-put overlay 'after-string after-string)
    (overlay-put overlay 'fringe-helper t)
    (overlay-put overlay 'window (selected-window))
    (overlay-put overlay 'priority (line-reminder--get-priority face))
    (push overlay line-reminder--thumbnail-overlays)
    overlay))

(defun line-reminder--make-thumb-overlays (list face)
  "Make thumbnail overlays with LIST and FACE."
  (when list
    (let ((window-lines (float (line-reminder--window-height)))
          (buffer-lines (float line-reminder--cache-max-line))
          percent-line)
      (when (< window-lines buffer-lines)
        (save-excursion
          (dolist (line list)
            (setq percent-line (* (/ line buffer-lines) window-lines)
                  percent-line (truncate percent-line))
            (move-to-window-line 0)
            (when (= (vertical-motion percent-line) percent-line)
              (line-reminder--create-thumb-overlay face))))))))

(defun line-reminder--show-thumb (window &rest _)
  "Show thumbnail using overlays."
  (with-selected-window window
    (line-reminder--make-thumb-overlays line-reminder--saved-lines 'line-reminder-saved-sign-face)
    (line-reminder--make-thumb-overlays line-reminder--change-lines 'line-reminder-modified-sign-face)))

(defvar-local line-reminder--thumbnail-timer nil
  "Timer to show thumbnail.")

(defun line-reminder--start-show-thumb (&optional window &rest _)
  "Start show thumbnail timer."
  (when line-reminder-thumbnail
    (line-reminder--delete-thumb-overlays)
    (when (timerp line-reminder--thumbnail-timer)
      (cancel-timer line-reminder--thumbnail-timer))
    (setq line-reminder--thumbnail-timer
          (run-with-idle-timer line-reminder-thumbnail-delay nil
                               #'line-reminder--show-thumb (or window (selected-window))))))

(defun line-reminder--delete-thumb-overlays ()
  "Delete overlays of thumbnail."
  (when line-reminder--thumbnail-overlays
    (mapc 'delete-overlay line-reminder--thumbnail-overlays)
    (setq line-reminder--thumbnail-overlays nil)))

(provide 'line-reminder)
;;; line-reminder.el ends here
