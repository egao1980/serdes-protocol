(in-package #:serdes-protocol)

(defvar *serdes-format* :json
  "Default serialization format keyword.")

(defvar *serdes-backend* nil
  "Optional current backend object for *SERDES-FORMAT*.")

(defvar *serdes-formats* (make-hash-table :test #'eq)
  "Map normalized format keywords to backend objects.")

(defclass serdes-backend () ()
  (:documentation "Base class for serdes-protocol backends."))

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

(defun %octet-vector-p (value)
  (and (vectorp value)
       (not (stringp value))
       (let ((et (array-element-type value)))
         (or (equal et '(unsigned-byte 8))
             (subtypep et '(unsigned-byte 8))))))

(defun encode-to-octets (value &key (format *serdes-format*))
  "Octets of VALUE. Binary formats may return octets from ENCODE (passed through);
   text formats are UTF-8 encoded."
  (let ((encoded (encode value :format format)))
    (if (%octet-vector-p encoded)
        encoded
        (babel:string-to-octets encoded :encoding :utf-8))))

(defun decode-octets (octets &key (format *serdes-format*))
  "Decode OCTETS using FORMAT. Backends accept octets or UTF-8 text."
  (decode octets :format format))
