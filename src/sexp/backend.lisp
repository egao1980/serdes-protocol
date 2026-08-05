(in-package #:sexp-protocol)

(defclass sexp-backend (serdes-backend) ())

(defun make-sexp-backend ()
  (make-instance 'sexp-backend))

(defun %key-string (key)
  (etypecase key
    (string key)
    (symbol (string-downcase (symbol-name key)))))

(defun %alist-p (value)
  (and (consp value)
       (every (lambda (entry)
                (and (consp entry)
                     (or (stringp (car entry)) (symbolp (car entry)))))
              value)))

(defun %plist-p (value)
  (and (listp value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             for key = (first tail)
             always (or (stringp key) (symbolp key)))))

(defun %to-sexpr (value)
  (cond
    ((hash-table-p value)
     (cons :object
           (loop for key being the hash-keys of value using (hash-value child)
                 collect (cons (%key-string key) (%to-sexpr child)))))
    ((%alist-p value)
     (cons :object
           (mapcar (lambda (entry)
                     (cons (%key-string (car entry)) (%to-sexpr (cdr entry))))
                   value)))
    ((and (consp value) (%plist-p value))
     (cons :object
           (loop for (key child) on value by #'cddr
                 collect (cons (%key-string key) (%to-sexpr child)))))
    ((stringp value) value)
    ((vectorp value)
     (map 'vector #'%to-sexpr value))
    ((consp value)
     (mapcar #'%to-sexpr value))
    (t value)))

(defun %entries-to-hash (entries)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry entries table)
      (setf (gethash (%key-string (car entry)) table)
            (%from-sexpr (cdr entry))))))

(defun %plist-to-hash (plist)
  (let ((table (make-hash-table :test #'equal)))
    (loop for (key child) on plist by #'cddr
          do (setf (gethash (%key-string key) table) (%from-sexpr child)))
    table))

(defun %from-sexpr (value)
  (cond
    ((and (consp value) (eq (car value) :object))
     (%entries-to-hash (cdr value)))
    ((%alist-p value)
     (%entries-to-hash value))
    ((and (consp value) (%plist-p value))
     (%plist-to-hash value))
    ((stringp value) value)
    ((vectorp value)
     (map 'vector #'%from-sexpr value))
    ((consp value)
     (mapcar #'%from-sexpr value))
    (t value)))

(defun %read-sexpr (source)
  (let ((*read-eval* nil)
        (*package* (find-package :cl-user))
        (eof (list :eof)))
    (labels ((read-one (stream)
               (let ((object (read stream nil eof)))
                 (when (eq object eof)
                   (error 'serdes-decode-error :message "empty S-expression input"))
                 object)))
      (etypecase source
        (string
         (with-input-from-string (stream source)
           (read-one stream)))
        ((vector (unsigned-byte 8))
         (with-input-from-string (stream (babel:octets-to-string source :encoding :utf-8))
           (read-one stream)))
        (stream
         (read-one source))))))

(defmethod backend-encode ((backend sexp-backend) value &key stream)
  (declare (ignore backend))
  (handler-case
      (let ((payload (%to-sexpr value)))
        (if stream
            (progn
              (prin1 payload stream)
              (values))
            (with-output-to-string (out)
              (prin1 payload out))))
    (serdes-error (e) (error e))
    (error (e)
      (error 'serdes-encode-error
             :message (format nil "sexp encode failed: ~A" e)))))

(defmethod backend-decode ((backend sexp-backend) source &key)
  (declare (ignore backend))
  (handler-case
      (%from-sexpr (%read-sexpr source))
    (serdes-error (e) (error e))
    (error (e)
      (error 'serdes-decode-error
             :message (format nil "sexp decode failed: ~A" e)))))

(defun use-sexp-backend ()
  "Register and select the S-expression backend. Returns the backend."
  (let ((backend (make-sexp-backend)))
    (register-format :sexp backend)
    (setf *serdes-format* :sexp
          *serdes-backend* backend)))

(use-sexp-backend)
