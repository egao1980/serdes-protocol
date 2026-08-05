(in-package #:serdes-protocol)

(defvar *serdes-format* :json
  "Default serialization format keyword.")

(defvar *serdes-backend* nil
  "Optional current backend object for *SERDES-FORMAT*.")

(defvar *serdes-formats* (make-hash-table :test #'eq)
  "Map normalized format keywords to backend objects.")

(defclass serdes-backend () ()
  (:documentation "Base class for serdes-protocol backends."))

(defclass serdes-input-stream () ()
  (:documentation "Marker class for future serdes input Gray streams."))

(defclass serdes-output-stream () ()
  (:documentation "Marker class for future serdes output Gray streams."))

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

(defgeneric backend-encode (backend value &key stream)
  (:documentation "Encode VALUE, returning a string unless STREAM is supplied."))

(defgeneric backend-decode (backend source &key)
  (:documentation "Decode SOURCE, usually a string, octet vector, or character stream."))

(defun %normalize-format (format)
  (etypecase format
    (keyword format)
    (symbol (intern (symbol-name format) :keyword))
    (string (intern (string-upcase format) :keyword))))

(defun register-format (format backend)
  "Register BACKEND for FORMAT and return BACKEND."
  (check-type backend serdes-backend)
  (setf (gethash (%normalize-format format) *serdes-formats*) backend))

(defun find-backend (format &optional (errorp t))
  "Return the backend registered for FORMAT.
When ERRORP is true, signal SERDES-UNKNOWN-FORMAT when the registry has no backend."
  (let* ((normalized (%normalize-format format))
         (backend (gethash normalized *serdes-formats*)))
    (cond
      (backend backend)
      (errorp
       (error 'serdes-unknown-format
              :format normalized
              :message "load or register a backend for this format"))
      (t nil))))

(defun %backend-for (format)
  (let ((normalized (%normalize-format format)))
    (or (and *serdes-backend*
             (eq normalized (%normalize-format *serdes-format*))
             *serdes-backend*)
        (find-backend normalized))))

(defun encode (value &key stream (format *serdes-format*))
  "Encode VALUE using the backend registered for FORMAT.
Returns a string unless STREAM is supplied."
  (handler-case
      (backend-encode (%backend-for format) value :stream stream)
    (serdes-error (e) (error e))
    (error (e)
      (error 'serdes-encode-error
             :message (format nil "encode failed for ~S: ~A" format e)))))

(defun decode (source &key (format *serdes-format*))
  "Decode SOURCE using the backend registered for FORMAT."
  (handler-case
      (backend-decode (%backend-for format) source)
    (serdes-error (e) (error e))
    (error (e)
      (error 'serdes-decode-error
             :message (format nil "decode failed for ~S: ~A" format e)))))

(defun encode-to-octets (value &key (format *serdes-format*))
  "UTF-8 octets of (ENCODE VALUE :FORMAT FORMAT)."
  (babel:string-to-octets (encode value :format format) :encoding :utf-8))

(defun decode-octets (octets &key (format *serdes-format*))
  "Decode UTF-8 OCTETS using FORMAT."
  (decode (babel:octets-to-string octets :encoding :utf-8) :format format))
