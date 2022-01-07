;;; dirvish-helpers.el --- Helper functions for Dirvish -*- lexical-binding: t -*-

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;;; Helper functions for dirvish.

;;; Code:

(declare-function dirvish-body-update "dirvish-body")
(declare-function dirvish--body-render-icon "dirvish-body")
(declare-function dirvish-header-update "dirvish-header")
(declare-function dirvish-footer-update "dirvish-footer")
(declare-function dirvish-preview-update "dirvish-preview")
(require 'dirvish-structs)
(require 'dirvish-vars)
(require 'dired-x)

(defmacro dirvish-with-update (full-update &rest body)
  "Do necessary cleanup, execute BODY, update current dirvish.

If FULL-UPDATE is non-nil, redraw icons and reset line height.

Some overlays such as icons, line highlighting, need to be
removed or updated before update current dirvish instance."
  (declare (indent 1))
  `(progn
     (when-let ((curr-dv (dirvish-curr)))
       (remove-overlays (point-min) (point-max) 'dirvish-body t)
       (when-let ((pos (dired-move-to-filename nil))
                  dirvish-show-icons)
         (remove-overlays (1- pos) pos 'dirvish-icons t)
         (dirvish--body-render-icon pos))
       ,@body
       (let ((skip (not ,full-update)))
         (dirvish-body-update skip skip))
       (when-let ((filename (dired-get-filename nil t)))
         (setf (dv-index-path curr-dv) filename)
         (dirvish-header-update)
         (dirvish-footer-update)
         (dirvish-debounce dirvish-preview-update dirvish-preview-delay)))))

(defmacro dirvish-repeat (func delay interval &rest args)
  "Execute FUNC with ARGS in every INTERVAL after DELAY."
  (let ((timer (intern (format "%s-timer" func))))
    `(progn
       (defvar ,timer nil)
       (add-to-list 'dirvish-repeat-timers ',timer)
       (setq ,timer (run-with-timer ,delay ,interval ',func ,@args)))))

(defmacro dirvish-debounce (func delay &rest args)
  "Execute a delayed version of FUNC with delay time DELAY.

When called, the FUNC only runs after the idle time
specified by DELAY.  Multiple calls to the same function before
the idle timer fires are ignored.  ARGS is arguments for FUNC."
  (let* ((timer (intern (format "%s-timer" func)))
         (do-once `(lambda (&rest args)
                     (unwind-protect (apply #',func args) (setq ,timer nil)))))
    `(progn
       (unless (boundp ',timer) (defvar ,timer nil))
       (unless (timerp ,timer)
         (setq ,timer (run-with-idle-timer ,delay nil ,do-once ,@args))))))

(defun dirvish-revert (&optional _arg _noconfirm)
  "Reread the Dirvish buffer.
Dirvish sets `revert-buffer-function' to this function.  See
`dired-revert'."
  (dirvish-with-update t (dired-revert)))

(defun dirvish--display-buffer (buffer alist)
  "Try displaying BUFFER at one side of the selected frame.

 This splits the window at the designated side of the
 frame.  ALIST is window arguments for the new-window, it has the
 same format with `display-buffer-alist'."
  (let* ((side (cdr (assq 'side alist)))
         (window-configuration-change-hook nil)
         (width (or (cdr (assq 'window-width alist)) 0.5))
         (height (cdr (assq 'window-height alist)))
         (size (or height (ceiling (* (frame-width) width))))
         (split-width-threshold 0)
         (root-win (dv-root-window (dirvish-curr)))
         (new-window (split-window-no-error root-win size side)))
    (window--display-buffer buffer new-window 'window alist)))

(defun dirvish--get-parent (path)
  "Get parent directory of PATH."
  (file-name-directory (directory-file-name (expand-file-name path))))

(defun dirvish--get-filesize (fileset)
  "Determine file size of provided list of files in FILESET."
  (unless (executable-find "du") (user-error "`du' executable not found"))
  (with-temp-buffer
    (apply #'call-process "du" nil t nil "-sch" fileset)
    (format "%s" (progn (re-search-backward "\\(^[0-9.,]+[a-zA-Z]*\\).*total$")
                        (match-string 1)))))

(defun dirvish--get-trash-dir ()
  "Get trash directory for current disk."
  (cl-dolist (dir dirvish-trash-dir-alist)
    (when (string-prefix-p (car dir) (dired-current-directory))
      (cl-return (concat (car dir) (cdr dir))))))

;;;###autoload
(defun dirvish-live-p (&optional win)
  "Detecting if WIN is in dirvish mode.

If WIN is nil, defaults to `\\(selected-window\\)'."
  (and
   (dirvish-curr)
   (memq (or win (selected-window)) (dv-parent-windows (dirvish-curr)))))

(provide 'dirvish-helpers)

;;; dirvish-helpers.el ends here
