(in-package #:serdes-protocol)

;;;; Gray stream wrappers + value-at-a-time / JSONL / event-parser GFs.

(defclass serdes-input-stream ()
  ((underlying :initarg :underlying :reader underlying-stream)
   (backend :initarg :backend :reader stream-backend)))

(defclass serdes-output-stream ()
  ((underlying :initarg :underlying :reader underlying-stream)
   (backend :initarg :backend :reader stream-backend)))

(defclass serdes-character-input-stream
    (serdes-input-stream trivial-gray-streams:fundamental-character-input-stream)
  ())

(defclass serdes-character-output-stream
    (serdes-output-stream trivial-gray-streams:fundamental-character-output-stream)
  ())

(defclass serdes-binary-input-stream
    (serdes-input-stream trivial-gray-streams:fundamental-binary-input-stream)
  ())

(defclass serdes-binary-output-stream
    (serdes-output-stream trivial-gray-streams:fundamental-binary-output-stream)
  ())

(defmethod stream-element-type ((s serdes-character-input-stream)) 'character)
(defmethod stream-element-type ((s serdes-character-output-stream)) 'character)
(defmethod stream-element-type ((s serdes-binary-input-stream)) '(unsigned-byte 8))
(defmethod stream-element-type ((s serdes-binary-output-stream)) '(unsigned-byte 8))

(defmethod trivial-gray-streams:stream-read-char ((s serdes-character-input-stream))
  (read-char (underlying-stream s) nil :eof))

(defmethod trivial-gray-streams:stream-unread-char ((s serdes-character-input-stream) char)
  (unread-char char (underlying-stream s)))

(defmethod trivial-gray-streams:stream-listen ((s serdes-character-input-stream))
  (listen (underlying-stream s)))

(defmethod trivial-gray-streams:stream-write-char ((s serdes-character-output-stream) char)
  (write-char char (underlying-stream s)))

(defmethod trivial-gray-streams:stream-line-column ((s serdes-character-output-stream))
  (ignore-errors (trivial-gray-streams:stream-line-column (underlying-stream s))))

(defmethod trivial-gray-streams:stream-finish-output ((s serdes-character-output-stream))
  (finish-output (underlying-stream s)))

(defmethod trivial-gray-streams:stream-force-output ((s serdes-character-output-stream))
  (force-output (underlying-stream s)))

(defmethod trivial-gray-streams:stream-read-byte ((s serdes-binary-input-stream))
  (read-byte (underlying-stream s) nil :eof))

(defmethod trivial-gray-streams:stream-write-byte ((s serdes-binary-output-stream) byte)
  (write-byte byte (underlying-stream s)))

(defmethod trivial-gray-streams:stream-finish-output ((s serdes-binary-output-stream))
  (finish-output (underlying-stream s)))

(defmethod trivial-gray-streams:stream-force-output ((s serdes-binary-output-stream))
  (force-output (underlying-stream s)))

(defmethod close ((s serdes-input-stream) &key abort)
  (close (underlying-stream s) :abort abort))

(defmethod close ((s serdes-output-stream) &key abort)
  (close (underlying-stream s) :abort abort))

;;; Factories

(defgeneric backend-make-input-stream (backend underlying &key element-type)
  (:documentation "Wrap UNDERLYING input stream for BACKEND."))

(defgeneric backend-make-output-stream (backend underlying &key element-type)
  (:documentation "Wrap UNDERLYING output stream for BACKEND."))

(defmethod backend-make-input-stream ((backend serdes-backend) underlying
                                      &key (element-type 'character))
  (cond
    ((subtypep element-type 'character)
     (make-instance 'serdes-character-input-stream
                    :underlying underlying :backend backend))
    ((equal element-type '(unsigned-byte 8))
     (make-instance 'serdes-binary-input-stream
                    :underlying underlying :backend backend))
    (t (error 'serdes-error
              :message (format nil "unsupported element-type ~S" element-type)))))

(defmethod backend-make-output-stream ((backend serdes-backend) underlying
                                       &key (element-type 'character))
  (cond
    ((subtypep element-type 'character)
     (make-instance 'serdes-character-output-stream
                    :underlying underlying :backend backend))
    ((equal element-type '(unsigned-byte 8))
     (make-instance 'serdes-binary-output-stream
                    :underlying underlying :backend backend))
    (t (error 'serdes-error
              :message (format nil "unsupported element-type ~S" element-type)))))

(defun %default-element-type (format)
  (if (format-binary-p format)
      '(unsigned-byte 8)
      'character))

(defun make-input-stream (underlying &key (format *serdes-format*)
                                       (element-type nil element-type-p))
  (backend-make-input-stream
   (%backend-for format) underlying
   :element-type (if element-type-p element-type (%default-element-type format))))

(defun make-output-stream (underlying &key (format *serdes-format*)
                                        (element-type nil element-type-p))
  (backend-make-output-stream
   (%backend-for format) underlying
   :element-type (if element-type-p element-type (%default-element-type format))))

;;; Value-at-a-time (JSONL / one-sexp-per-line)

(defgeneric stream-encode-value (stream value &key)
  (:documentation "Write one VALUE (e.g. one JSON line + newline)."))

(defgeneric stream-decode-value (stream &key)
  (:documentation "Read one complete value, or :eof."))

(defmethod stream-encode-value ((stream serdes-character-output-stream) value &key)
  (backend-encode (stream-backend stream) value :stream (underlying-stream stream))
  (write-char #\Newline (underlying-stream stream))
  value)

(defmethod stream-decode-value ((stream serdes-character-input-stream) &key)
  (let ((line (read-line (underlying-stream stream) nil :eof)))
    (if (eq line :eof)
        :eof
        (backend-decode (stream-backend stream) line))))

;;; JSONL helpers

(defun %open-jsonl-source (source)
  "→ (values stream close-fn). SOURCE = stream | string | pathname | octets."
  (etypecase source
    (stream (values source (constantly nil)))
    (string
     (let ((s (make-string-input-stream source)))
       (values s (lambda () (close s)))))
    ((vector (unsigned-byte 8))
     (let ((s (make-string-input-stream
               (babel:octets-to-string source :encoding :utf-8))))
       (values s (lambda () (close s)))))
    (pathname
     (let ((s (open source :direction :input :external-format :utf-8)))
       (values s (lambda () (close s)))))))

(defun map-jsonl (function source &key (format :json))
  "Call FUNCTION with each decoded top-level value from a JSONL SOURCE."
  (multiple-value-bind (raw close) (%open-jsonl-source source)
    (unwind-protect
         (let ((in (make-input-stream raw :format format)))
           (loop for v = (stream-decode-value in)
                 until (eq v :eof)
                 do (funcall function v)))
      (funcall close)))
  (values))

(defmacro do-jsonl ((var source &key (format :json)) &body body)
  `(map-jsonl (lambda (,var) ,@body) ,source :format ,format))

;;; Event / pull parse

(defclass serdes-event-parser ()
  ((backend :initarg :backend :reader event-parser-backend)
   (source :initarg :source :reader event-parser-source)))

(defgeneric backend-make-event-parser (backend source &key max-depth max-string-length)
  (:documentation "SOURCE = stream | pathname | octets | string."))

(defgeneric parse-next-event (parser)
  (:documentation "→ (values event value). EVENT nil at EOF."))

(defgeneric parse-next-element (parser &key)
  (:documentation "Optional: consume next complete sub-value as one Lisp object."))

(defmethod backend-make-event-parser ((backend serdes-backend) source
                                      &key max-depth max-string-length)
  (declare (ignore source max-depth max-string-length))
  (error 'serdes-error
         :message (format nil "event parser not implemented for ~A"
                          (class-name (class-of backend)))))

(defmethod parse-next-event ((parser serdes-event-parser))
  (error 'serdes-error :message "parse-next-event not implemented"))

(defmethod parse-next-element ((parser serdes-event-parser) &key)
  (error 'serdes-error :message "parse-next-element not implemented"))

(defun make-event-parser (source &key (format *serdes-format*)
                                   max-depth max-string-length)
  (backend-make-event-parser (%backend-for format) source
                             :max-depth max-depth
                             :max-string-length max-string-length))

(defmacro with-event-parser ((var source &key (format '*serdes-format*)) &body body)
  (let ((fmt (gensym "FMT")))
    `(let ((,fmt ,format)
           (,var (make-event-parser ,source :format ,fmt)))
       ,@body)))

(defun map-events (function source &key (format *serdes-format*))
  "Call FUNCTION with (event value) for each pull-parse event until EOF."
  (let ((parser (make-event-parser source :format format)))
    (loop
      (multiple-value-bind (event value) (parse-next-event parser)
        (unless event (return))
        (funcall function event value))))
  (values))
